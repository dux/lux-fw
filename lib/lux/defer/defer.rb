require 'timeout'

module Lux
  # Background-work pool for fire-and-forget jobs (logging, mail, audit
  # trails). Workers spawn lazily up to Lux.config.defer_pool_size and die
  # after IDLE_TIMEOUT_SECS of inactivity. When the queue is saturated the
  # job runs inline on the caller (caller-runs overflow) so backpressure is
  # automatic and no work is dropped.
  #
  # Public entry point is the existing Lux.defer shim
  # (lib/lux/current/lux_adapter.rb), which delegates here.
  module Defer
    DEFAULT_POOL_SIZE ||= 3
    IDLE_TIMEOUT_SECS ||= 60

    @mutex     ||= Mutex.new
    @queue     ||= Queue.new
    @worker_ct ||= 0

    class << self
      def submit context: nil, timeout: nil, &block
        raise ArgumentError, 'Block not given' unless block

        context   = Lux.current.dup if context.nil?
        timeout ||= Lux.config.delay_timeout
        raise 'Timeout is not numeric (seconds)' unless timeout.is_a?(Numeric)

        job = build_job(block, context, timeout)

        ensure_worker

        # Caller-runs overflow: when queued work already exceeds pool capacity
        # the call site runs the job synchronously. Gives natural backpressure
        # without dropping work.
        if @queue.size >= pool_size
          run_inline(job)
        else
          @queue << job
        end

        nil
      end

      def pool_size
        size = Lux.config[:defer_pool_size] if defined?(Lux.config) && Lux.config.respond_to?(:[])
        size || DEFAULT_POOL_SIZE
      end

      def stats
        @mutex.synchronize { { workers: @worker_ct, queued: @queue.size, pool_size: pool_size } }
      end

      private

      # Wraps the user block with timeout and error reporting. The Timeout
      # check uses wall time because Timeout::Error inherits from
      # StandardError and can be silently rescued by inner `rescue => e`
      # blocks - we only know for sure a timeout fired by measuring elapsed
      # time, not by the exception class that bubbles out.
      def build_job block, context, timeout
        -> do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            ::Timeout::timeout(timeout) do
              block.arity == 0 ? block.call : block.call(context)
            end
          rescue => e
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
            if elapsed >= timeout
              log.error 'Lux.defer timeout after %.2fs / %ss limit (rescued %s: %s)' % [
                elapsed, timeout, e.class, e.message
              ]
            else
              log.error(['Lux.defer error: %s: %s' % [e.class, e.message], e.backtrace&.first(20)].flatten.compact.join($/))
            end
          ensure
            Thread.current[:lux] = nil
          end
        end
      end

      def ensure_worker
        @mutex.synchronize { spawn_worker if @worker_ct < pool_size }
      end

      def spawn_worker
        @worker_ct += 1

        Thread.new do
          begin
            loop do
              # Queue#pop(timeout:) returns nil on idle expiry (Ruby 3.2+);
              # nil means the worker dies and the next submit will respawn.
              job = @queue.pop(timeout: IDLE_TIMEOUT_SECS)
              break unless job
              job.call
            end
          rescue => e
            log.error 'Lux.defer worker died: %s: %s' % [e.class, e.message]
          ensure
            @mutex.synchronize { @worker_ct -= 1 }
          end
        end
      end

      # Inline overflow path. The job's ensure block nils Thread.current[:lux]
      # so we save/restore around the call to keep the caller's request
      # context intact.
      def run_inline job
        saved = Thread.current[:lux]
        begin
          job.call
        ensure
          Thread.current[:lux] = saved
        end
      end

      def log
        Lux.logger(:defer_worker)
      end
    end
  end
end
