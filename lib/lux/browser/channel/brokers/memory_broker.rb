require_relative 'base'

module Lux
  class Browser
    module Channel
      # In-process only - publish is a direct local fan-out.
      #
      # Nothing crosses a process boundary, so a push from a job process never
      # reaches a browser held by the web process. Right default for dev, test
      # and single-process servers; point channel_url at `postgres:` once the
      # app grows a second process.
      class MemoryBroker < Broker
        def publish name, data
          Lux::Browser::Channel.local_publish name, data
          true
        end
      end
    end
  end
end
