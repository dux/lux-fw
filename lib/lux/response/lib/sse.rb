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
        # last_event_id: the browser's Last-Event-ID header on a reconnect.
        # Anything retained by Channel newer than that is replayed before we
        # start streaming live, so a dropped connection does not eat messages.
        def initialize channels, last_event_id = nil
          @channels      = channels
          @last_event_id = last_event_id
        end

        def each
          queue = Queue.new
          subs  = @channels.map { |c| Lux::Browser::Channel.subscribe(c, queue) }

          yield ": connected\n\n"

          # Subscribe first, then replay: the reverse order would drop anything
          # published in between. The cost is that a message can be both
          # replayed and queued, so remember what we sent and skip it below.
          sent = {}

          if @last_event_id
            @channels
              .flat_map { |c| Lux::Browser::Channel.history_since(c, @last_event_id) }
              .sort_by  { |m| m[:id].to_i }
              .each do |m|
                sent[m[:channel]] = m[:id].to_i
                yield format_event(m[:channel], m[:data], m[:id])
              end
          end

          loop do
            msg = pop_with_timeout(queue, HEARTBEAT_INTERVAL)

            if msg
              last = sent[msg[:channel]]
              next if last && msg[:id].to_i <= last
              yield format_event(msg[:channel], msg[:data], msg[:id])
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

        # Every frame is the same shape: {channel, data} as JSON on the default
        # message event. The client routes on the channel field, so a connection
        # needs no per-channel event listeners and never reopens.
        #
        # JSON.generate escapes newlines, so the payload cannot break framing -
        # which a raw String payload could, since SSE needs `data: ` per line.
        def format_event channel, data, id = nil
          frame = +''
          frame << "id: #{id}\n" if id
          frame << "data: #{JSON.generate(channel: channel, data: data)}\n\n"
        end
      end
    end
  end
end
