# LuxJob.init
# Thread.new { LuxJob.run }

class LuxJob < ApplicationModel
  schema do
    name
    opts Hash
    retry_count Integer, default: 0
    run_at Time, index: true
    status_sid max: 1, default: 's'
    response?
    created_at Time
    updated_at Time

    db :add_index, :run_at
  end

  ###

  JOBS ||= {}

  class << self
    def define name, every: nil, &block
      JOBS[name] = { proc: block }
      JOBS[name][:name] = name.to_s
      JOBS[name][:every] = every if every
    end

    def init
      return if Lux.env.cli?
      init!
    end

    def init!
      JOBS.values.each do |opts|
        if every = opts[:every]
          LuxJob.first_or_create(name: opts[:name])
        end
      end
    end

    def run
      LuxJobLock.with_lock do
        verbose = ENV['LUX_LIVE'] != 'true'

        puts "Registered jobs:"
        if JOBS.empty?
          puts "  (none)"
        else
          JOBS.each do |name, opts|
            if duration = opts[:every]
              parts = duration.parts.map { |unit, val| "#{val} #{unit}" }.join(', ')
              every = " (every #{parts})"
            else
              every = " (on demand)"
            end
            puts "  - #{name}#{every}"
          end
        end
        puts

        unless verbose
          puts "Not showing spinner because LUX_LIVE=true"
          puts
        end

        spinner = %w[| / - \\]
        spinner_idx = 0

        loop do
          sleep 3
          process_jobs verbose: verbose
        end
      end
    end

    def add name, opts = {}
      job_def = JOBS[name.to_sym]

      # For recurring jobs, update existing record to run now
      if job_def && job_def[:every]
        existing = LuxJob.first(name: name.to_s)
        if existing
          existing.update(opts: opts, run_at: Time.now - 1.day, status_sid: 's')
          return existing
        end
      end

      # For on-demand jobs or if no existing record, create new
      LuxJob.create name: name, opts: opts, run_at: Time.now - 1.day
    end

    def run_job job, verbose: false
      opts = JOBS[job.name.to_sym] || begin
        Lux.info "LuxJob ERROR: Job [#{job.name}] not defined"
        job.delete
        return
      end

      begin
        # Set run_at to future immediately to prevent duplicate runs
        next_run = opts[:every] ? Time.now + opts[:every] : Time.now + 1.hour
        job.update status_sid: 'r', run_at: next_run

        response = opts[:proc].call job.opts.to_hwia
        if response.class == String && response.length < 255
          job.response = response
        else
          job.response = ''
        end
        job.status_sid = 'd'
        job.retry_count = 0

        log_data = job.response.or('done')
        log_data += " - #{job.opts.to_json}" if job.opts.keys.length > 0
        job.log log_data, verbose: verbose

        if opts[:every]
          job.save
        else
          job.delete
        end

      rescue => error
        msg = "ERROR: #{error.message} (#{error.class}) #{error.backtrace[0]}"
        job.response = msg
        job.log msg, verbose: verbose
        job.retry_count += 1
        job.run_at = Time.now + job.retry_count.minutes
        job.status_sid = 'f'
        job.save
        puts "[#{Time.now.strftime('%H:%M:%S')}] #{job.name}: #{msg}" if verbose
      end
    end

    def process_jobs verbose: false
      jobs = LuxJob.where { run_at < Time.now }.exclude(name: LuxJobLock::LOCK_NAME).all
      jobs.each do |job|
        run_job job, verbose: verbose
      end
    end
  end

  enums :statuses, field: :status_sid, method: :status do |t|
    t[:s] = 'Scheduled'
    t[:r] = 'Running'
    t[:f] = 'Failed'
    t[:d] = 'Done'
  end

  ###

  validate do
    self[:retry_count] ||= 0
    self[:status_sid] ||= 's'
    self[:run_at] ||= Time.now
  end

  def path
  end

  def admin_path
    "/admin/lux_jobs/#{sid}"
  end

  def log line, verbose: false
    msg = "[#{self.name}] #{line}"
    Lux.logger(:lux_job).info msg
    print "[#{Time.now.strftime('%H:%M:%S')}] #{msg}\n" if verbose
  end

  def log_lines
    `grep -i '\\[#{name}\\]' ./log/lux_job.log | tac | tail -n 100`
  end
end
