module Lux
  module Shell
    # Raised by Lux.shell.exec when the command fails and no block is given.
    # Carries the failed argv plus captured streams so callers / handlers can
    # inspect them.
    class Error < StandardError
      attr_reader :command, :err, :out

      def initialize command, err, out = ''
        @command = Array(command)
        @err     = err.to_s
        @out     = out.to_s
        tail = @err.strip
        msg  = 'shell failed: %s' % @command.inspect
        msg << "\n" << tail unless tail.empty?
        super msg
      end
    end
  end
end
