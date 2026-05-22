require 'json'

module Lux
  class Response
    # Server-Sent Events writer. Subscribes to one or more Lux::Channel names
    # and streams messages to the client until disconnect.
    #
    #   response.sse :notifications, "user:#{u.id}"
    #
    # Client side: see assets/lux/sse.js (window.Lux.sse).
    module Sse
      HEARTBEAT_INTERVAL ||= 30   # seconds; sent as `: ping\n\n` to keep proxies alive

      def self.apply response, *channels
        raise ArgumentError, 'sse needs at least one channel' if channels.empty?

        h = response.headers
        h['content-type']      = 'text/event-stream; charset=utf-8'
        h['cache-control']     = 'no-cache, no-transform'
        h['connection']        = 'keep-alive'
        h['x-accel-buffering'] = 'no'   # nginx: do not buffer

        response.stream StreamBody.new(channels.map(&:to_s))
      end

      # Iterable body that subscribes to channels in #each and yields formatted
      # SSE frames until the client disconnects or an error tears the stream.
      class StreamBody
        def initialize channels
          @channels = channels
        end

        def each
          queue = Queue.new
          subs  = @channels.map { |c| Lux::Channel.subscribe(c, queue) }

          yield ": connected\n\n"

          loop do
            msg = pop_with_timeout(queue, HEARTBEAT_INTERVAL)
            if msg
              yield format_event(msg[:channel], msg[:data])
            else
              yield ": ping\n\n"
            end
          end
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          # client disconnect - normal exit
        ensure
          subs&.each(&:close)
        end

        private

        # Queue#pop(timeout:) landed in Ruby 3.2. Fall back to a poll loop
        # otherwise so we don't hard-depend on 3.2.
        def pop_with_timeout queue, seconds
          if queue.method(:pop).parameters.any? { |_, name| name == :timeout }
            queue.pop(timeout: seconds)
          else
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
            until Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
              begin
                return queue.pop(true)
              rescue ThreadError
                sleep 0.05
              end
            end
            nil
          end
        end

        def format_event channel, data
          payload = data.is_a?(String) ? data : JSON.generate(data)
          "event: #{channel}\ndata: #{payload}\n\n"
        end
      end
    end
  end
end
