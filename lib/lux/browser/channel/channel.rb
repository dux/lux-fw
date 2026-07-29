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
      # Messages retained per channel for Last-Event-ID replay after a client
      # reconnects. LISTEN/NOTIFY has no replay of its own, so this is the only
      # thing standing between a dropped connection and silently lost messages.
      HISTORY_SIZE ||= 100

      extend self

      @lock    ||= Mutex.new
      @subs    ||= {}   # channel_name (String) -> [Queue, ...]
      @history ||= {}   # channel_name (String) -> [[id, data], ...]
      @seq     ||= {}   # channel_name (String) -> last id assigned here

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
      # The id is assigned here, by the publishing process, and travels with the
      # message so every listener agrees on it. Replay therefore assumes a single
      # publisher per channel - two processes publishing to the same name will
      # hand out the same ids. That matches how channels are used in practice
      # (one job, one channel); if you need multiple publishers, make the channel
      # name unique per publisher.
      def publish name, data
        name = name.to_s
        id   = next_id(name)

        if PgBroker.publish_enabled?
          PgBroker.publish(name, data, id)
        else
          local_publish(name, data, id)
        end
      end

      # Direct in-process fan-out, bypassing the broker. Used by PgBroker to
      # deliver an inbound NOTIFY without bouncing it back through NOTIFY again,
      # and by tests that exercise the queue path without a DB.
      def local_publish name, data, id = nil
        name    = name.to_s
        id    ||= next_id(name)
        message = { channel: name, data: data, id: id }

        queues = @lock.synchronize do
          log = (@history[name] ||= [])
          log << [id, data]
          log.shift while log.size > HISTORY_SIZE
          (@subs[name] || []).dup
        end

        queues.each { |q| q.push(message) }
      end

      # Messages retained for `name` newer than `last_id`, oldest first. Used to
      # catch a reconnecting EventSource up on what it missed.
      def history_since name, last_id
        name    = name.to_s
        last_id = last_id.to_i

        @lock.synchronize do
          (@history[name] || [])
            .select { |id, _| id > last_id }
            .map    { |id, data| { channel: name, data: data, id: id } }
        end
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

      # What a browser connection receives is derived from its session, never
      # from the request - a client cannot ask for a channel, so there is
      # nothing to authorize. Set this once in an initializer:
      #
      #   Lux::Browser::Channel.session_channels do |lux|
      #     user = lux.current.user or next []
      #     ["user:#{user.ref}", "org:#{user.org_ref}"]
      #   end
      #
      # Return [] for an anonymous visitor; /_lux_/stream then refuses to open.
      # A resolver that raises is treated as [].
      def session_channels &block
        return @session_channels = block if block
        @session_channels
      end

      def channels_for lux
        return [] unless @session_channels
        Array(@session_channels.call(lux)).map(&:to_s).reject(&:empty?).uniq
      rescue => e
        Lux.logger(:channel).error("session_channels raised: #{e.message}") rescue nil
        []
      end

      # Diagnostic helpers (not part of the public hot path).
      def channels
        @lock.synchronize { @subs.keys.dup }
      end

      def subscriber_count name
        @lock.synchronize { (@subs[name.to_s] || []).size }
      end

      # Test/admin only - drop every subscriber, channel and retained message.
      def reset!
        @lock.synchronize do
          @subs    = {}
          @history = {}
          @seq     = {}
        end
        @session_channels = nil
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

      # Restart the listener in a forked child - the thread does not survive
      # fork, only its socket does. Called from the puma worker-boot hook, so
      # an app that calls pg_listen! in an initializer (which runs in the
      # master) still ends up with a listening worker.
      def pg_after_fork!
        PgBroker.after_fork!
      end

      def pg_publishing?
        PgBroker.publish_enabled?
      end

      def pg_listening?
        PgBroker.listening?
      end

      private

      def next_id name
        @lock.synchronize { @seq[name] = (@seq[name] || 0) + 1 }
      end
    end
  end
end

require_relative 'pg_broker'

# Register the SSE client module so /_lux_/sse.js works.
Lux::Browser.register :sse, file: 'assets/lux/sse.js'
