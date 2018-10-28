module Lux::DelayedJob
  module Redis
    extend self

    def que
      @server ||= Lux.config(:redis_server)
    end

    def push(list)
      que.push Marshal.dump list
    end

    def pop
      que.process(true) do |message|
        Marshal.load(message) rescue nil
      end
    end
  end
end
