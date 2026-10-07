require 'json'

module Lux
  class Response
    # Server-Sent Events writer. Subscribes to one or more Lux::Browser::Channel
    # names and streams messages to the client until disconnect.
    #
    #   response.sse :notifications, "user:#{u.id}"
    #
    # Every frame is {channel, data} as JSON on the default message event, so
    # one connection carries any number of channels and the client routes on
    # the channel field. Normally you want /_lux_/stream (one session-scoped
    # stream per browser) rather than calling this from an action.
    #
    # Client side: see assets/lux/sse.js (window.Lux.subscribe).
    module Sse
      HEARTBEAT_INTERVAL ||= 30   # seconds; sent as `: ping\n\n` to keep proxies alive

      # EventSource reconnect delay, randomised per connection so a deploy does
      # not bring every tab back in the same instant.
      RETRY_MS ||= 1000..5000

      # One SSE frame - for a hand-rolled `response.stream` body, e.g. streamed
      # LLM tokens. A Hash/Array goes out as JSON (never breaks framing); a
      # String is split into one `data:` line per line.
      #
      #   Lux::Response::Sse.frame({ token: 'Hi' }, event: :token)
      def self.frame data, event: nil
        lines = data.is_a?(String) ? data.split("\n", -1) : [JSON.generate(data)]
        out   = event ? "event: #{event}\n" : +''
        lines.each { out << "data: #{_1}\n" }
        out << "\n"
      end

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

        # Nothing is replayed: a connection receives what is published while it
        # is open, and that is all. A tab that reconnects mid-run has missed
        # whatever went out in the gap, so send state a client can re-fetch
        # rather than deltas it must have seen.
        #
        # Every message frame is {channel, data} as JSON on the default message
        # event; the client routes on the channel field, so a connection needs
        # no per-channel listeners and never reopens. {resync: true} says
        # messages may have been lost.
        def each
          queue = Queue.new
          subs  = @channels.map { |c| Lux::Browser::Channel.subscribe(c, queue) }

          yield "retry: #{rand(RETRY_MS)}\n: connected\n\n"

          loop do
            msg = pop_with_timeout(queue, HEARTBEAT_INTERVAL)

            if msg.nil?
              yield ": ping\n\n"
            elsif msg[:close]
              break
            elsif msg[:resync]
              yield Sse.frame({ resync: true })
            else
              yield Sse.frame({ channel: msg[:channel], data: msg[:data] })
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
      end
    end
  end
end
