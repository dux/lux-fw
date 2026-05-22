module Lux
  # Lux::Channel - in-process pub/sub backbone for SSE streams.
  #
  #   Lux.channel(:notifications).push(message: 'Hello')
  #   Lux.channel("user:#{u.id}").push(type: :inbox, count: 3)
  #
  # Consumed by `response.sse(*channels)` in a controller action; one
  # EventSource on the client multiplexes events tagged by channel name.
  #
  # v1 is in-process only. Publish from worker A reaches subscribers in
  # worker A; cross-worker fan-out (PG LISTEN/NOTIFY broker, mirroring
  # plugins/job_runner) is a future addition.
  module Channel
    extend self

    @lock ||= Mutex.new
    @subs ||= {}   # channel_name (String) -> [Queue, ...]

    Publisher    ||= Struct.new(:name) do
      def push data
        Lux::Channel.publish(name, data)
      end
    end

    Subscription ||= Struct.new(:channel, :queue) do
      def close
        Lux::Channel.unsubscribe(channel, queue)
      end
    end

    # Lux::Channel[:foo] -> Publisher; .push(data) fans out to all subscribers.
    def [] name
      Publisher.new(name.to_s)
    end

    # Broadcast `data` (any JSON-serialisable value, or String) to every queue
    # currently subscribed to `name`.
    def publish name, data
      name = name.to_s
      message = { channel: name, data: data }
      queues = @lock.synchronize { (@subs[name] || []).dup }
      queues.each { |q| q.push(message) }
    end

    # Attach `queue` (typically a SizedQueue or Queue) to a channel. Returns a
    # Subscription handle; call .close to detach.
    def subscribe name, queue
      name = name.to_s
      @lock.synchronize do
        @subs[name] ||= []
        @subs[name]  << queue
      end
      Subscription.new(name, queue)
    end

    def unsubscribe name, queue
      name = name.to_s
      @lock.synchronize do
        list = @subs[name] or next
        list.delete(queue)
        @subs.delete(name) if list.empty?
      end
    end

    # Diagnostic helpers (not part of the public hot path).
    def channels
      @lock.synchronize { @subs.keys.dup }
    end

    def subscriber_count name
      @lock.synchronize { (@subs[name.to_s] || []).size }
    end

    # Test/admin only - drop every subscriber and channel.
    def reset!
      @lock.synchronize { @subs = {} }
    end
  end
end

# Register the SSE client module with Lux::Browser so /lux/sse.js works.
Lux::Browser.register :sse, file: 'assets/lux/sse.js' if defined?(Lux::Browser)
