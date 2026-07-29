module Lux
  class Browser
    module Channel
      # Broker contract - moves a published message from the process that
      # pushed it to every process holding subscribers for that channel.
      #
      #   publish(name, data)  required; deliver however this backend does it
      #   listen!              start receiving; hand inbound messages to
      #                        Channel.local_publish. No-op when in-process.
      #   stop!                release whatever listen! took
      #   after_fork!          re-arm in a forked child (see PgBroker)
      #
      # Only publish is mandatory - a broker with no cross-process story
      # inherits the no-op rest. Which one is used comes from a single config
      # key, Lux.config.channel_url (ENV['CHANNEL_URL'] wins), so swapping the
      # backend never touches Channel itself.
      class Broker
        # scheme -> file basename under ./brokers, which must define
        # Lux::Browser::Channel::<Name>Broker.
        SCHEMES ||= {
          'memory'     => 'memory',
          'postgres'   => 'pg',
          'postgresql' => 'pg',
        }.freeze

        attr_reader :url

        def initialize url = nil
          @url = url.to_s
        end

        def publish name, data
          raise NotImplementedError, '%s must implement #publish' % self.class
        end

        def listen!     ; false end
        def stop!       ; false end
        def after_fork! ; false end
        def listening?  ; false end

        # Empty / nil is memory, so an app that never configures anything still
        # works in-process. Otherwise the scheme picks the broker and everything
        # after it is that broker's to interpret.
        def self.build url
          url    = url.to_s.strip
          scheme = url.empty? ? 'memory' : url.split(':', 2).first.to_s.downcase
          name   = SCHEMES[scheme]

          unless name
            raise ArgumentError,
              "unknown channel_url scheme #{scheme.inspect} - expected one of: #{SCHEMES.keys.sort.join(', ')}"
          end

          require_relative '%s_broker' % name
          Lux::Browser::Channel.const_get('%sBroker' % name.capitalize).new(url)
        end
      end
    end
  end
end
