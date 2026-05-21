module Lux
  class Policy
    class Error < StandardError
    end

    class << self
      def error msg
        raise Lux::Policy::Error.new(msg)
      end
    end

    def error message
      raise Lux::Policy::Error.new(message)
    end
  end
end
