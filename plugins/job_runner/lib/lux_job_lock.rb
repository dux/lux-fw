# Single-instance guard for LuxJob runner using a Postgres advisory lock.
#
# The lock is session-scoped: it lives only as long as the PG connection
# that acquired it. If the runner process dies (crash, kill, host reboot,
# network partition), Postgres releases the lock automatically and the
# next runner can take over - no stale row, no heartbeat.
#
# The lock MUST be held on a pinned connection (the same one used for
# LISTEN). Don't return that connection to the pool while running.
#
# Usage (see LuxJob.run):
#   DB.synchronize do |conn|
#     LuxJobLock.acquire!(conn)
#     # ... LISTEN + work loop on `conn` ...
#     LuxJobLock.release(conn)
#   end

class LuxJobLock
  # Two-int4 advisory lock key. Using the (classid, objid) form so the
  # holder query can match exact columns in pg_locks - the bigint form
  # splits the key across columns and makes the query awkward.
  LOCK_CLASSID ||= 0
  LOCK_OBJID   ||= 0x4C58_4A42  # 'LXJB' as ascii

  # Seconds between liveness checks (see LuxJob.start_liveness_check).
  LIVENESS_INTERVAL ||= 180

  class << self
    def acquire!(conn)
      got = conn.exec("SELECT pg_try_advisory_lock(#{LOCK_CLASSID}, #{LOCK_OBJID})").getvalue(0, 0)
      unless got == 't' || got == true
        Lux.shell.die [
          'Job runner already running',
          "pid: #{holder_pid.inspect}"
        ]
      end
      Lux.shell.info "LuxJobLock: acquired advisory lock (backend pid #{backend_pid(conn)})"
    end

    def release(conn)
      conn.exec("SELECT pg_advisory_unlock(#{LOCK_CLASSID}, #{LOCK_OBJID})")
      Lux.shell.info "LuxJobLock: released advisory lock"
    rescue => e
      Lux.shell.info "LuxJobLock: release failed: #{e.message}"
    end

    def backend_pid(conn)
      conn.exec("SELECT pg_backend_pid()").getvalue(0, 0).to_i
    end

    # PID of the backend currently holding our advisory lock, or nil.
    # Queried via the pool (not the pinned connection), so it's safe to
    # call from the liveness-check thread without contending with LISTEN.
    def holder_pid
      row = DB.fetch(
        "SELECT pid FROM pg_locks
         WHERE locktype = 'advisory'
           AND classid = ? AND objid = ? AND objsubid = 1
           AND granted = true",
        LOCK_CLASSID, LOCK_OBJID
      ).first
      row && row[:pid]
    end
  end
end
