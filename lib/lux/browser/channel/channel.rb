module Lux
  class Browser
    # Lux::Browser::Channel - in-process pub/sub backbone for SSE streams.
    #
    #   Lux.channel(:notifications).push(message: 'Hello')
    #   Lux.channel("user:#{u.id}").push(type: :inbox, count: 3)
    #
    # Consumed by `response.sse(*channels)` in a controller action; one
    # EventSource on the client multiplexes events tagged by channel name.
    #
    # In-process by default. For cross-worker fan-out (PG LISTEN/NOTIFY):
    #
    #   # config/puma.rb (publish + receive)
    #   on_worker_boot { Lux::Browser::Channel.pg_listen! }
    #
    #   # in job / rake / one-off processes (publish only)
    #   Lux::Browser::Channel.pg_publish!
    module Channel
      extend self

      @lock ||= Mutex.new
      @subs ||= {}   # channel_name (String) -> [Queue, ...]

      Publisher    ||= Struct.new(:name) do
        def push data
          Lux::Browser::Channel.publish(name, data)
        end
      end

      Subscription ||= Struct.new(:channel, :queue) do
        def close
          Lux::Browser::Channel.unsubscribe(channel, queue)
        end
      end

      # Lux::Browser::Channel[:foo] -> Publisher; .push(data) fans out to all subscribers.
      def [] name
        Publisher.new(name.to_s)
      end

      # Broadcast `data` (any JSON-serialisable value, or String) to every queue
      # currently subscribed to `name`. When PG publish is enabled (pg_publish!
      # or pg_listen!), this is routed through NOTIFY so every process listening
      # on the same DB receives it via its own LISTEN connection.
      def publish name, data
        if PgBroker.publish_enabled?
          PgBroker.publish(name.to_s, data)
        else
          local_publish(name, data)
        end
      end

      # Direct in-process fan-out, bypassing the broker. Used by PgBroker to
      # deliver an inbound NOTIFY without bouncing it back through NOTIFY again,
      # and by tests that exercise the queue path without a DB.
      def local_publish name, data
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

      # PG LISTEN/NOTIFY shortcuts. See PgBroker for details and caveats.
      # `pg_publish!` routes Channel.publish through NOTIFY (use in jobs).
      # `pg_listen!` also starts the LISTEN thread (use in Puma workers).
      def pg_publish! db_name: :main
        PgBroker.enable_publish!(db_name: db_name)
      end

      def pg_listen! db_name: :main
        PgBroker.enable_listen!(db_name: db_name)
      end

      def pg_stop!
        PgBroker.stop!
      end

      def pg_publishing?
        PgBroker.publish_enabled?
      end

      def pg_listening?
        PgBroker.listening?
      end
    end
  end
end

require_relative 'pg_broker'

# Register the SSE client module so /lux/sse.js works.
Lux::Browser.register :sse, file: 'assets/lux/sse.js'
