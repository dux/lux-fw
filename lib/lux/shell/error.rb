module Lux
  module Shell
    # Raised by Lux.shell.exec(..., raise: true) or Result#out! on failure.
    # Carries the full Result via .result so callers can inspect stdout/stderr.
    class Error < StandardError
      attr_reader :result

      def initialize result
        @result = result
        super build_message(result)
      end

      private

      def build_message r
        msg = 'shell failed: %s (exit %s)' % [r.command.inspect, r.exitstatus.inspect]
        msg << ' [TIMED OUT]' if r.timed_out?
        tail = r.err.to_s.strip
        msg << "\n" << tail unless tail.empty?
        msg
      end
    end
  end
end
