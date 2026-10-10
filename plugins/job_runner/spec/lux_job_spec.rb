require 'test_helper'
require_relative 'support/db'

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

    it 'accepts a per-job retry limit' do
      LuxJob.define(:flaky, retries: 2) { 'done' }

      _(LuxJob::JOBS[:flaky][:retries]).must_equal 2
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

    it 'permanently fails after the per-job retry limit' do
      LuxJob.define(:short_fuse, retries: 2) { raise 'fails' }
      job = LuxJob.create(name: 'short_fuse', run_at: Time.now - 1.minute, retry_count: 1)

      LuxJob.run_job(job)
      job.reload

      _(job.status_sid).must_equal 'x'
      _(job.retry_count).must_equal 2
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

    it 'finishes the job in flight on stop and skips the rest' do
      ran = []
      LuxJob.define(:first)  { sleep 0.3; ran << :first; 'done' }
      LuxJob.define(:second) { ran << :second; 'done' }
      LuxJob.create(name: 'first',  run_at: Time.now - 2.minutes)
      LuxJob.create(name: 'second', run_at: Time.now - 1.minute)

      runner = Thread.new { LuxJob.process_jobs }
      runner.report_on_exception = false
      sleep 0.1
      runner.raise LuxJobStop

      assert_raises(LuxJobStop) { runner.join }
      _(ran).must_equal [:first]
      _(LuxJob.first.name).must_equal 'second'
    end

    it 'finishes the job in flight on a lost lock instead of swallowing it' do
      ran = []
      LuxJob.define(:first)  { sleep 0.3; ran << :first; 'done' }
      LuxJob.define(:second) { ran << :second; 'done' }
      LuxJob.create(name: 'first',  run_at: Time.now - 2.minutes)
      LuxJob.create(name: 'second', run_at: Time.now - 1.minute)

      runner = Thread.new { LuxJob.process_jobs }
      runner.report_on_exception = false
      sleep 0.1
      runner.raise LuxJobLockLost, 'lost'

      assert_raises(LuxJobLockLost) { runner.join }
      _(ran).must_equal [:first]
      _(LuxJob.first.name).must_equal 'second'
    end

    it 'skips permanently failed jobs' do
      LuxJob.define(:dead_job) { 'done' }
      LuxJob.create(name: 'dead_job', run_at: Time.now - 1.minute, status_sid: 'x')

      LuxJob.process_jobs

      _(LuxJob.first.status_sid).must_equal 'x'
    end
  end

  describe '.recover_interrupted' do
    it 're-queues jobs left running by a killed runner' do
      LuxJob.define(:cut_off) { 'done' }
      LuxJob.create(name: 'cut_off', run_at: Time.now + 1.hour, status_sid: 'r')

      capture_stdout { capture_stderr { LuxJob.recover_interrupted } }

      job = LuxJob.first
      _(job.status_sid).must_equal 's'
      assert job.run_at <= Time.now
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
end
