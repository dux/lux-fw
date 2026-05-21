module Lux
  module Shell
    # Structured result from Lux.shell.exec. Read-only; do not mutate.
    class Result
      attr_reader :command, :out, :err, :status, :duration

      def initialize command:, out:, err:, status:, duration:, timed_out: false
        @command   = command
        @out       = out || ''
        @err       = err || ''
        @status    = status
        @duration  = duration.to_f
        @timed_out = timed_out ? true : false
      end

      def exitstatus
        @status.respond_to?(:exitstatus) ? @status.exitstatus : nil
      end

      def success?
        !timed_out? && @status && @status.respond_to?(:success?) && @status.success? ? true : false
      end

      def timed_out?
        @timed_out
      end

      def err?
        !@err.to_s.empty?
      end

      # Stdout split into chomped lines.
      def lines
        @out.lines.map(&:chomp)
      end

      # Stdout stripped of surrounding whitespace.
      def strip
        @out.strip
      end

      # Stdout (stripped) on success, raises Lux::Shell::Error otherwise.
      def out!
        raise Lux::Shell::Error.new(self) unless success?
        @out.strip
      end

      # Parse stdout as JSON. Returns nil on parse error; use json! to raise.
      def json
        require 'json'
        JSON.parse(@out)
      rescue JSON::ParserError
        nil
      end

      def json!
        require 'json'
        JSON.parse(@out)
      end

      def to_h
        {
          command:    @command,
          exitstatus: exitstatus,
          out:        @out,
          err:        @err,
          duration:   @duration,
          timed_out:  timed_out?,
          success:    success?
        }
      end

      def inspect
        '#<Lux::Shell::Result %s exit=%s dur=%.3fs%s>' % [
          @command.inspect, exitstatus.inspect, @duration,
          (timed_out? ? ' TIMED_OUT' : '')
        ]
      end
      alias_method :to_s, :inspect
    end
  end
end
