require 'test_helper'

# --- DB bootstrap ---------------------------------------------------------
Object.send(:remove_const, :DB) if defined?(DB)
DB ||= Sequel.connect('postgres:///lux_fw_test')
DB.extension :pg_array, :pg_json
DB.loggers.clear

# Load just enough of the db plugin to get the schema DSL, hooks and enums.
require_relative '../../db/loader.rb'
Sequel::Model.plugin :lux_schema
Sequel::Model.plugin :lux_hooks
Sequel::Model.plugin :lux_before_save

# Host-level ApplicationModel stand-in: ref primary key with auto-fill.
unless defined?(ApplicationModel)
  ApplicationModel = Class.new(Sequel::Model) do
    set_primary_key :ref
    unrestrict_primary_key
    plugin :lux_schema

    def before_create
      self[:ref] ||= Lux::Utils::Ref.generate
      super
    end
  end
end

# Fresh table for each run, matching the LuxJob schema.
DB.drop_table?(:lux_jobs)

DB.create_table :lux_jobs do
  String  :ref, primary_key: true
  String  :name
  jsonb   :opts, default: Sequel.lit("'{}'::jsonb"), null: false
  Integer :retry_count, default: 0
  Time    :run_at, index: true
  String  :status_sid, size: 1, default: 's'
  String  :response, text: true
  Time    :created_at
  Time    :updated_at
end

# job.log writes through Lux.logger(:lux_job); keep it off disk.
Lux::LOGGER_CACHE[:lux_job] = Logger.new(IO::NULL)

# Sweeps load/ (LuxJob, LuxJobLock, the lux_job exporter).
Lux::Plugin.load File.expand_path('..', __dir__)

###

describe LuxJob do
  before do
    LuxJob.dataset.delete
    LuxJob::JOBS.clear
  end

  describe '.define' do
    it 'registers a job without interval' do
      LuxJob.define(:test_job) { 'done' }

      assert_kind_of ::Hash, LuxJob::JOBS[:test_job]
      _(LuxJob::JOBS[:test_job][:name]).must_equal 'test_job'
      assert_nil LuxJob::JOBS[:test_job][:every]
    end

    it 'registers a job with interval' do
      LuxJob.define(:recurring_job, every: 1.hour) { 'done' }

      _(LuxJob::JOBS[:recurring_job][:every]).must_equal 1.hour
    end

    it 'uses default timeout when none specified' do
      LuxJob.define(:no_timeout) { 'done' }

      _(LuxJob::JOBS[:no_timeout][:timeout]).must_equal LuxJob::DEFAULT_TIMEOUT
    end

    it 'accepts custom timeout' do
      LuxJob.define(:custom_timeout, timeout: 300) { 'done' }

      _(LuxJob::JOBS[:custom_timeout][:timeout]).must_equal 300
    end
  end

  describe '.add' do
    it 'creates a job record scheduled to run immediately' do
      LuxJob.define(:send_email) { |opts| "sent to #{opts[:to]}" }

      job = LuxJob.add(:send_email, { to: 'test@example.com' })

      assert_kind_of LuxJob, job
      _(job.name).must_equal 'send_email'
      # jsonb round-trips with string keys; run_job hands the proc a Lux::Hash
      _(job.opts['to']).must_equal 'test@example.com'
      assert job.run_at < Time.now
      _(job.status_sid).must_equal 's'
    end
  end

  describe '.run_job' do
    it 'executes job and marks as done' do
      LuxJob.define(:simple_job) { 'completed' }
      job = LuxJob.create(name: 'simple_job', run_at: Time.now - 1.minute)

      LuxJob.run_job(job)

      # one-off jobs are deleted
      _(LuxJob.count).must_equal 0
    end

    it 'reschedules recurring jobs' do
      LuxJob.define(:recurring, every: 1.hour) { 'done' }
      job = LuxJob.create(name: 'recurring', run_at: Time.now - 1.minute)

      LuxJob.run_job(job)
      job.reload

      _(job.status_sid).must_equal 'd'
      assert job.run_at > Time.now
    end

    it 'handles job failures with retry and 60% backoff' do
      LuxJob.define(:failing_job) { raise 'oops' }
      job = LuxJob.create(name: 'failing_job', run_at: Time.now - 1.minute)

      LuxJob.run_job(job)
      job.reload

      _(job.status_sid).must_equal 'f'
      _(job.retry_count).must_equal 1
      # first retry: RETRY_BASE_WAIT * 1.6^0 = 60s
      assert_in_delta (Time.now + LuxJob::RETRY_BASE_WAIT).to_f, job.run_at.to_f, 5
    end

    it 'increases retry delay by 60% each attempt' do
      LuxJob.define(:backoff_job) { raise 'fail' }
      job = LuxJob.create(name: 'backoff_job', run_at: Time.now - 1.minute, retry_count: 3)

      LuxJob.run_job(job)
      job.reload

      # retry_count is now 4, delay = 60 * 1.6^3 = 245.76s
      expected_delay = LuxJob::RETRY_BASE_WAIT * (1.6 ** 3)
      assert_in_delta (Time.now + expected_delay).to_f, job.run_at.to_f, 5
      _(job.status_sid).must_equal 'f'
    end

    it 'permanently fails after MAX_RETRIES' do
      LuxJob.define(:doomed_job) { raise 'always fails' }
      job = LuxJob.create(
        name: 'doomed_job',
        run_at: Time.now - 1.minute,
        retry_count: LuxJob::MAX_RETRIES - 1
      )

      LuxJob.run_job(job)
      job.reload

      _(job.status_sid).must_equal 'x'
      _(job.status).must_equal 'Permanently failed'
      _(job.retry_count).must_equal LuxJob::MAX_RETRIES
    end

    it 'times out jobs that exceed their timeout' do
      LuxJob.define(:slow_job, timeout: 1) { sleep 5 }
      job = LuxJob.create(name: 'slow_job', run_at: Time.now - 1.minute)

      LuxJob.run_job(job)
      job.reload

      _(job.status_sid).must_equal 'f'
      _(job.retry_count).must_equal 1
      _(job.response).must_include 'Timeout'
    end

    it 'deletes undefined jobs' do
      job = LuxJob.create(name: 'undefined_job', run_at: Time.now - 1.minute)

      capture_stdout { capture_stderr { LuxJob.run_job(job) } }

      _(LuxJob.count).must_equal 0
    end
  end

  describe '.process_jobs' do
    it 'processes only jobs due to run' do
      LuxJob.define(:job1) { 'done1' }
      LuxJob.define(:job2) { 'done2' }

      LuxJob.create(name: 'job1', run_at: Time.now - 1.minute)
      LuxJob.create(name: 'job2', run_at: Time.now + 1.hour)

      LuxJob.process_jobs

      _(LuxJob.count).must_equal 1
      _(LuxJob.first.name).must_equal 'job2'
    end

    it 'skips running jobs' do
      LuxJob.define(:running_job) { 'done' }
      LuxJob.create(name: 'running_job', run_at: Time.now - 1.minute, status_sid: 'r')

      LuxJob.process_jobs

      # still there and still marked running, not picked up again
      _(LuxJob.first.status_sid).must_equal 'r'
    end

    it 'skips permanently failed jobs' do
      LuxJob.define(:dead_job) { 'done' }
      LuxJob.create(name: 'dead_job', run_at: Time.now - 1.minute, status_sid: 'x')

      LuxJob.process_jobs

      _(LuxJob.first.status_sid).must_equal 'x'
    end
  end

  describe 'status enum' do
    it 'maps status codes to labels' do
      job = LuxJob.new(status_sid: 's')
      _(job.status).must_equal 'Scheduled'

      job.status_sid = 'r'
      _(job.status).must_equal 'Running'

      job.status_sid = 'f'
      _(job.status).must_equal 'Failed'

      job.status_sid = 'd'
      _(job.status).must_equal 'Done'

      job.status_sid = 'x'
      _(job.status).must_equal 'Permanently failed'
    end
  end

  describe '#admin_path' do
    it 'links to the admin show page by name' do
      job = LuxJob.create(name: 'test', run_at: Time.now)
      _(job.admin_path).must_equal '/admin/plugins/lux_jobs/show?name=test'
    end
  end
end
