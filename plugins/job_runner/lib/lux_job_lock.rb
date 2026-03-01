# Single instance guard for LuxJob runner
# Uses database record with heartbeat to ensure only one runner is active
#
# Usage:
#   LuxJobLock.with_lock do
#     # ... do work ...
#   end

require 'socket'

class LuxJobLock
  LOCK_NAME = '__job_runner_lock__'
  HEARTBEAT_INTERVAL = 10  # seconds
  STALE_THRESHOLD = 30     # seconds

  attr_reader :lock_id

  def initialize
    @lock_id = "#{Socket.gethostname}:#{Process.pid}"
    @heartbeat_thread = nil
  end

  def self.with_lock(&block)
    lock = new
    lock.acquire!
    lock.start_heartbeat
    yield
  ensure
    lock.stop_heartbeat
    lock.release
  end

  def acquire!
    existing = LuxJob.first(name: LOCK_NAME)

    if existing
      if stale?(existing)
        old_owner = existing.opts['locked_by'] || existing.opts[:locked_by]
        existing.update(
          opts: { locked_by: @lock_id },
          run_at: Time.now,
          updated_at: Time.now
        )
        Lux.info "LuxJobLock: Took over stale lock from #{old_owner}"
      else
        locked_by = existing.opts['locked_by'] || existing.opts[:locked_by]
        raise "Job runner already running (#{locked_by} since #{existing.created_at})"
      end
    else
      LuxJob.create(
        name: LOCK_NAME,
        opts: { locked_by: @lock_id },
        run_at: Time.now,
        status_sid: 'r'
      )
      Lux.info "LuxJobLock: Acquired lock as #{@lock_id}"
    end
  end

  def release
    LuxJob.where(name: LOCK_NAME).delete
    Lux.info "LuxJobLock: Released lock"
  rescue => e
    Lux.info "LuxJobLock: Error releasing lock: #{e.message}"
  end

  def start_heartbeat
    @heartbeat_thread = Thread.new do
      loop do
        sleep HEARTBEAT_INTERVAL
        update_heartbeat
      end
    end
  end

  def stop_heartbeat
    @heartbeat_thread&.kill
    @heartbeat_thread = nil
  end

  def update_heartbeat
    LuxJob.where(name: LOCK_NAME).update(run_at: Time.now)
  rescue => e
    Lux.info "LuxJobLock: Heartbeat error: #{e.message}"
  end

  private

  def stale?(lock_record)
    lock_record.run_at < Time.now - STALE_THRESHOLD
  end
end
