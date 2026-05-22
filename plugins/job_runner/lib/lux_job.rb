# LuxJob.init
# Thread.new { LuxJob.run }

require 'timeout'

class LuxJobError < StandardError; end

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

  MAX_RETRIES     ||= 7
  RETRY_BASE_WAIT ||= 60  # seconds, grows by 60% each retry
  DEFAULT_TIMEOUT ||= 60  # seconds

  # PG LISTEN/NOTIFY channel used to wake the runner when a job is enqueued
  # so we don't have to poll the DB on a fixed interval.
  NOTIFY_CHANNEL ||= 'lux_jobs'
  MIN_WAKE_SECS  ||= 1
  MAX_WAKE_SECS  ||= 300

  class << self
    def define name, every: nil, timeout: nil, &block
      JOBS[name] = { proc: block }
      JOBS[name][:name] = name.to_s
      JOBS[name][:every] = every if every
      JOBS[name][:timeout] = timeout || DEFAULT_TIMEOUT
    end

    def init
      return if Lux.runtime.cli?
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

      # Sweep any leftover rows from the previous row-based lock scheme.
      LuxJob.where(name: '__job_runner_lock__').delete

      # One pinned connection holds the advisory lock AND the LISTEN
      # subscription. If this connection dies the lock is auto-released
      # by Postgres - the liveness thread catches that case below.
      DB.synchronize do |conn|
        LuxJobLock.acquire!(conn)
        our_pid  = LuxJobLock.backend_pid(conn)
        liveness = start_liveness_check(our_pid)

        begin
          conn.exec("LISTEN #{NOTIFY_CHANNEL}")

          # Initial sweep covers anything due at startup before we wait.
          process_jobs verbose: verbose

          loop do
            # wait_for_notify needs a block, so pass an empty one.
            conn.wait_for_notify(next_wake_seconds) {}
            process_jobs verbose: verbose
          end
        ensure
          liveness&.kill
          conn.exec("UNLISTEN *") rescue nil
          LuxJobLock.release(conn)
        end
      end
    end

    # Periodically verifies that our pinned connection still holds the
    # advisory lock. If Sequel silently reconnects, or the network blips
    # and PG releases the lock, the holder pid will no longer match ours
    # (or will be nil). Exiting lets the supervisor restart cleanly -
    # the restarted process will re-acquire the lock.
    def start_liveness_check(our_pid)
      Thread.new do
        Thread.current.name = 'lux_job_liveness'
        loop do
          sleep LuxJobLock::LIVENESS_INTERVAL
          holder = LuxJobLock.holder_pid
          if holder != our_pid
            Lux.shell.error "LuxJob: lost advisory lock (holder=#{holder.inspect}, expected=#{our_pid}). Exiting for supervisor restart."
            Process.exit(1)
          end
        rescue => e
          Lux.shell.info "LuxJob: liveness check error: #{e.message}"
        end
      end
    end

    def add name, opts = {}
      job_def = JOBS[name.to_sym]

      job =
        if job_def && job_def[:every]
          # For recurring jobs, update existing record to run now
          existing = LuxJob.first(name: name.to_s)
          if existing
            existing.update(opts: opts, run_at: Time.now - 1.day, status_sid: 's')
            existing
          end
        end

      # For on-demand jobs or if no existing record, create new
      job ||= LuxJob.create(name: name, opts: opts, run_at: Time.now - 1.day)

      notify_listeners
      job
    end

    # Fire NOTIFY so a blocked runner wakes immediately instead of waiting
    # for the next scheduled poll window. Safe to call from any process.
    def notify_listeners
      DB.run "NOTIFY #{NOTIFY_CHANNEL}"
    rescue => e
      Lux.shell.info "LuxJob: NOTIFY failed: #{e.message}"
    end

    # Seconds until the next due job; bounded so we still wake periodically
    # even when nothing is queued (acts as a heartbeat for missed NOTIFYs).
    def next_wake_seconds
      next_at = LuxJob
        .exclude(status_sid: ['r', 'x'])
        .min(:run_at)

      return MAX_WAKE_SECS unless next_at
      (next_at - Time.now).clamp(MIN_WAKE_SECS, MAX_WAKE_SECS)
    end

    def error msg
      raise LuxJobError, msg
    end

    def run_job job, verbose: false
      opts = JOBS[job.name.to_sym] || begin
        Lux.shell.error "LuxJob ERROR: Job [#{job.name}] not defined"
        job.delete
        return
      end

      begin
        # Set run_at to future immediately to prevent duplicate runs
        next_run = opts[:every] ? Time.now + opts[:every] : Time.now + 1.hour
        job.update status_sid: 'r', run_at: next_run

        timeout = opts[:timeout] || DEFAULT_TIMEOUT
        response = Timeout.timeout(timeout) { opts[:proc].call job.opts.to_lux_hash }
        if response.is_a?(String) && response.length < 255
          job.response = response
        else
          job.response = ''
        end
        job.status_sid = 'd'
        job.retry_count = 0

        log_data = job.response.or('done')
        log_data += " - #{job.opts.to_json}" if job.opts.any?
        job.log log_data, verbose: verbose

        if opts[:every]
          job.save
        else
          job.delete
        end

      rescue LuxJobError => e
        job.response = "ERROR: #{e.message}"
        job.status_sid = 'f'
        job.log "#{e.message}", verbose: verbose
        job.save

      rescue => e
        Lux.config.error_logger&.call(e)

        msg = "UNHANDLED: #{e.message} (#{e.class}) #{e.backtrace&.first}"
        job.response = msg
        job.retry_count += 1

        if job.retry_count >= MAX_RETRIES
          job.status_sid = 'x'
          job.log "PERMANENTLY FAILED after #{MAX_RETRIES} retries: #{msg}", verbose: verbose
        else
          delay = RETRY_BASE_WAIT * (1.6 ** (job.retry_count - 1))
          job.run_at = Time.now + delay
          job.status_sid = 'f'
          job.log msg, verbose: verbose
        end

        job.save
      end
    end

    def process_jobs verbose: false
      jobs = LuxJob
        .where { run_at < Time.now }
        .exclude(status_sid: ['r', 'x'])
        .all
      jobs.each do |job|
        run_job job, verbose: verbose
      end
    end

    # --- View helpers (used by the admin dashboard templates) ------------
    # Kept on the model so templates don't need helper-module wiring; these
    # only format LuxJob fields and never grow into general utilities.

    def time_ago(time)
      return '' unless time
      diff = Time.now - time
      case diff
      when 0..59       then "#{diff.to_i}s ago"
      when 60..3599    then "#{(diff / 60).to_i}m ago"
      when 3600..86399 then "#{(diff / 3600).to_i}h ago"
      else                  "#{(diff / 86400).to_i}d ago"
      end
    end

    def time_relative(time)
      return '' unless time
      diff = time - Time.now
      past = diff < 0
      diff = diff.abs
      val = case diff
            when 0..59       then "#{diff.to_i}s"
            when 60..3599    then "#{(diff / 60).to_i}m"
            when 3600..86399 then "#{(diff / 3600).to_i}h"
            else                  "#{(diff / 86400).to_i}d"
            end
      past ? "#{val} ago" : "in #{val}"
    end

    def status_css(status)
      return '' unless status
      "status-#{status.downcase.gsub(/\s+/, '-')}"
    end

    # Matches the standard Logger format: "[YYYY-MM-DDTHH:MM:SS.sss #pid] LEVEL -- : message"
    LOG_LINE_RE ||= /\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.\d+ \#\d+\]\s+\w+ -- : (.+)/

    def parse_log_line(line)
      if line =~ LOG_LINE_RE
        time = Time.parse($1) rescue nil
        { time: time, message: $2 }
      else
        { time: nil, message: line }
      end
    end

    def safe_job_name(name)
      name.to_s.gsub(/[^a-zA-Z0-9_\-]/, '')
    end

    # Read N most-recent log lines for a job (or all jobs if name is nil).
    # Returns lines newest-first.
    def tail_log(name: nil, lines: 100)
      cmd = if name
        "grep -i '\\[#{safe_job_name(name)}\\]' ./log/lux_job.log 2>/dev/null | tail -n #{lines.to_i}"
      else
        "tail -n #{lines.to_i} ./log/lux_job.log 2>/dev/null"
      end
      Lux.shell.capture(cmd, shell: true).split("\n").reverse
    end

    # Last log timestamp ("id") for the auto-refresh poller. Returns nil
    # if no log entries yet.
    def last_log_id(name: nil)
      cmd = if name
        "grep -i '\\[#{safe_job_name(name)}\\]' ./log/lux_job.log 2>/dev/null | tail -n 1"
      else
        "tail -n 1 ./log/lux_job.log 2>/dev/null"
      end
      line = Lux.shell.capture(cmd, shell: true).strip
      line =~ /\[(\d{4}-\d{2}-\d{2}T[\d:\.]+)/ ? $1 : nil
    end
  end

  enums :statuses, field: :status_sid, method: :status do |t|
    t[:s] = 'Scheduled'
    t[:r] = 'Running'
    t[:f] = 'Failed'
    t[:d] = 'Done'
    t[:x] = 'Permanently failed'
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
    safe_name = name.to_s.gsub(/[^a-zA-Z0-9_\-]/, '')
    Lux.shell.capture("grep -i '\\[#{safe_name}\\]' ./log/lux_job.log | tac | tail -n 100", shell: true)
  end
end
