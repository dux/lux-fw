# require 'spec_helper'

RSpec.describe LuxJob do
  before(:each) do
    LuxJob.dataset.delete
    LuxJob::JOBS.clear
  end

  describe '.define' do
    it 'registers a job without interval' do
      LuxJob.define(:test_job) { 'done' }

      expect(LuxJob::JOBS[:test_job]).to be_a(Hash)
      expect(LuxJob::JOBS[:test_job][:name]).to eq('test_job')
      expect(LuxJob::JOBS[:test_job][:every]).to be_nil
    end

    it 'registers a job with interval' do
      LuxJob.define(:recurring_job, every: 1.hour) { 'done' }

      expect(LuxJob::JOBS[:recurring_job][:every]).to eq(1.hour)
    end
  end

  describe '.add' do
    it 'creates a job record scheduled to run immediately' do
      LuxJob.define(:send_email) { |opts| "sent to #{opts[:to]}" }

      job = LuxJob.add(:send_email, { to: 'test@example.com' })

      expect(job).to be_a(LuxJob)
      expect(job.name).to eq('send_email')
      expect(job.opts[:to]).to eq('test@example.com')
      expect(job.run_at).to be < Time.now
      expect(job.status_sid).to eq('s')
    end
  end

  describe '.run_job' do
    it 'executes job and marks as done' do
      LuxJob.define(:simple_job) { 'completed' }
      job = LuxJob.create(name: 'simple_job', run_at: Time.now - 1.minute)

      LuxJob.run_job(job)

      expect(LuxJob.count).to eq(0) # one-off jobs are deleted
    end

    it 'reschedules recurring jobs' do
      LuxJob.define(:recurring, every: 1.hour) { 'done' }
      job = LuxJob.create(name: 'recurring', run_at: Time.now - 1.minute)

      LuxJob.run_job(job)
      job.reload

      expect(job.status_sid).to eq('d')
      expect(job.run_at).to be > Time.now
    end

    it 'handles job failures with retry' do
      LuxJob.define(:failing_job) { raise 'oops' }
      job = LuxJob.create(name: 'failing_job', run_at: Time.now - 1.minute)

      LuxJob.run_job(job)
      job.reload

      expect(job.status_sid).to eq('f')
      expect(job.retry_count).to eq(1)
      expect(job.run_at).to be > Time.now
    end

    it 'deletes undefined jobs' do
      job = LuxJob.create(name: 'undefined_job', run_at: Time.now - 1.minute)

      LuxJob.run_job(job)

      expect(LuxJob.count).to eq(0)
    end
  end

  describe '.process_jobs' do
    it 'processes only jobs due to run' do
      LuxJob.define(:job1) { 'done1' }
      LuxJob.define(:job2) { 'done2' }

      LuxJob.create(name: 'job1', run_at: Time.now - 1.minute)
      LuxJob.create(name: 'job2', run_at: Time.now + 1.hour)

      LuxJob.process_jobs

      expect(LuxJob.count).to eq(1)
      expect(LuxJob.first.name).to eq('job2')
    end
  end

  describe 'status enum' do
    it 'maps status codes to labels' do
      job = LuxJob.new(status_sid: 's')
      expect(job.status).to eq('Scheduled')

      job.status_sid = 'r'
      expect(job.status).to eq('Running')

      job.status_sid = 'f'
      expect(job.status).to eq('Failed')

      job.status_sid = 'd'
      expect(job.status).to eq('Done')
    end
  end

  describe '#admin_path' do
    it 'returns admin path' do
      job = LuxJob.create(name: 'test', run_at: Time.now)
      expect(job.admin_path).to eq("/admin/lux_jobs/#{job.sid}")
    end
  end
end
