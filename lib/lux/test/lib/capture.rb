require 'stringio'

module Lux
  module Test
    # capture_log { ... } returns whatever Lux.log wrote during the block.
    # capture_stdout { ... } returns whatever was written to $stdout.
    # capture_stderr { ... } returns whatever was written to $stderr.
    module Capture
      def capture_log
        buf  = StringIO.new
        prev = Lux.instance_variable_get(:@default_logger)
        Lux.instance_variable_set(:@default_logger, ::Logger.new(buf))
        yield
        buf.string
      ensure
        Lux.instance_variable_set(:@default_logger, prev)
      end

      def capture_stdout
        prev = $stdout
        $stdout = StringIO.new
        yield
        $stdout.string
      ensure
        $stdout = prev
      end

      def capture_stderr
        prev = $stderr
        $stderr = StringIO.new
        yield
        $stderr.string
      ensure
        $stderr = prev
      end
    end
  end
end
