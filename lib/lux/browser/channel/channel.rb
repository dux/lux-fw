module Lux
  class Browser
    # Lux::Browser::Channel - pub/sub backbone for SSE streams.
    #
    #   Lux.channel(user).push(html: 'Done')          # -> "user:<ref>"
    #   Lux.channel("user:#{ref}").push(count: 3)
    #
    # A channel name IS its audience: a browser only ever receives what its own
    # session resolves to (see session_channels), so pushing to a user reaches
    # that person and nobody else. Consumed by /_lux_/stream, or by
    # `response.sse(*channels)` in an action.
    #
    # Delivery across processes is the broker's job, picked by one config key:
    #
    #   Lux.config.channel_url = 'postgres:main'   # or ENV['CHANNEL_URL']
    #
    # Unset means in-process only. See ./brokers/base.rb for the contract.
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

      # Lux::Browser::Channel[user] -> Publisher; .push(data) fans out.
      def [] name
        Publisher.new(channel_name(name))
      end

      # A model becomes "<model>:<ref>". A String or Symbol is taken as-is but
      # must name its audience, so a bare ref cannot silently become a channel
      # nobody is listening to.
      #
      # underscore turns "Admin::Report" into "admin/report", and a "/" is not
      # a legal channel name (Mount::CHANNEL_NAME) - the endpoint would drop it
      # and the push would vanish without an error. Namespace separators become
      # ":" instead, so a namespaced model addresses "admin:report:<ref>".
      def channel_name target
        if target.is_a?(String) || target.is_a?(Symbol)
          name = target.to_s
          raise ArgumentError, "channel needs a prefix, got #{name.inspect}" unless name.include?(':')
          return name
        end

        raise ArgumentError, "cannot derive a channel from #{target.class}" unless target.respond_to?(:ref)

        '%s:%s' % [target.class.name.underscore.tr('/', ':'), target.ref]
      end

      # Send `data` (any JSON-serialisable value, or String) to every subscriber
      # of `name`, in this process and any other the broker reaches.
      def publish name, data
        broker.publish name.to_s, data
      end

      # Direct in-process fan-out, bypassing the broker. Brokers call this to
      # deliver an inbound message without bouncing it back out again.
      def local_publish name, data
        name    = name.to_s
        message = { channel: name, data: data }

        queues = @lock.synchronize { (@subs[name] || []).dup }
        queues.each { |q| q.push(message) }
      end

      # Attach `queue` (typically a Queue) to a channel. Returns a Subscription
      # handle; call .close to detach.
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

      # Built once from Lux.config.channel_url; ENV wins so a single process can
      # be pointed elsewhere without touching config.
      def broker
        @broker ||= Broker.build(ENV['CHANNEL_URL'] || Lux.config[:channel_url])
      end

      # Escape hatch for tests and for an app that builds its own.
      def broker= value
        @broker = value
      end

      # What a browser connection receives is derived from its session, never
      # from the request - a client cannot ask for a channel, so there is
      # nothing to authorize. Set this once in an initializer:
      #
      #   Lux::Browser::Channel.session_channels do |lux|
      #     ref = lux.session[:user_ref] or next []
      #     ["user:#{ref}"]
      #   end
      #
      # Return [] for an anonymous visitor; /_lux_/stream then refuses to open.
      # A resolver that raises is treated as [].
      #
      # Note it runs before route resolution, so a current-user helper set up by
      # a controller filter is not available yet - read the session directly.
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

      # Test/admin only - drop every subscriber and release the broker, so the
      # next publish rebuilds it from current config.
      def reset!
        @lock.synchronize { @subs = {} }
        @broker&.stop! rescue nil
        @broker           = nil
        @session_channels = nil
      end
    end
  end
end

require_relative 'brokers/base'
require_relative 'brokers/memory_broker'

# Register the SSE client module so /_lux_/sse.js works.
Lux::Browser.register :sse, file: 'assets/lux/sse.js'
