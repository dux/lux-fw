require 'test_helper'

describe Lux::Error do
  before { Lux::Current.new('http://testing') }

  describe 'as an exception class' do
    it 'is a StandardError with no HTTP knowledge' do
      err = Lux::Error.new('something broke')
      _(err).must_be_kind_of StandardError
      _(err.message).must_equal 'something broke'
      _(err.respond_to?(:code)).must_equal false
    end
  end

  describe '.format' do
    it 'formats backtrace with error class, message, and indented paths' do
      error = StandardError.new('test')
      error.set_backtrace([
        "#{Lux.root}/app/controllers/main.rb:10:in `index'",
        "/Users/user/.gem/gems/rack-2.2.4/lib/rack/request.rb:20:in `call'"
      ])

      result = Lux::Error.format(error, message: true)
      _(result).must_be_kind_of String
      lines = result.split("\n")
      _(lines[0].start_with?('URL: ')).must_equal true   # request URL header
      _(lines[1]).must_equal '[StandardError] test'
      _(lines[2].start_with?('  ./')).must_equal true   # local app line
      _(lines[3].start_with?('  /')).must_equal true    # gem line
    end

    it 'returns string marker when no backtrace' do
      error = StandardError.new('test')
      _(Lux::Error.format(error)).must_equal 'no backtrace present'
      _(Lux::Error.format(error, message: true)).must_include '[StandardError] test'
    end
  end
end

describe 'Lux.error' do
  before { Lux::Current.new('http://testing') }

  def with_error_log_buffer
    buf = StringIO.new
    logger = Logger.new(buf)
    logger.formatter = proc { |_, _, _, msg| "#{msg}\n" }
    logger.level = Logger::INFO

    prev = Lux.instance_variable_get(:@default_logger)
    Lux.instance_variable_set(:@default_logger, logger)
    yield buf
  ensure
    Lux.instance_variable_set(:@default_logger, prev)
  end

  def with_log_custom(custom)
    prev = Lux::ErrorProxy.method(:log_custom)
    Lux::ErrorProxy.define_singleton_method(:log_custom, &custom)
    yield
  ensure
    Lux::ErrorProxy.define_singleton_method(:log_custom) { |error| prev.call(error) }
  end

  def with_debug_mode(value)
    prev = Lux.mode.debug?
    Lux.mode.debug = value
    yield
  ensure
    Lux.mode.debug = prev
  end

  describe 'with integer code' do
    it 'returns Lux::Error and sets response status to that code' do
      err = Lux.error 404
      _(err).must_be_instance_of Lux::Error
      _(Lux.current.response.status).must_equal 404
    end

    it 'fills the message from Rack::Utils::HTTP_STATUS_CODES when none given' do
      err = Lux.error 404
      _(err.message).must_equal 'Not Found'
    end

    it 'uses the custom message when provided' do
      err = Lux.error 404, 'missing thing'
      _(err.message).must_equal 'missing thing'
      _(Lux.current.response.status).must_equal 404
    end

    it 'prints the debug screen error in red' do
      with_debug_mode(true) do
        with_error_log_buffer do |buf|
          Lux.error 404

          _(buf.string).must_include "\e[31m Lux.error 404"
          _(buf.string).must_include "\e[0m"
        end
      end
    end
  end

  describe 'with message only (no code)' do
    it 'defaults to status 400 and uses the given message' do
      err = Lux.error 'oops'
      _(err.message).must_equal 'oops'
      _(Lux.current.response.status).must_equal 400
    end
  end

  describe 'with no args' do
    it 'returns the ErrorProxy for chained shortcuts' do
      _(Lux.error).must_equal Lux::ErrorProxy
    end
  end

  describe 'proxy shortcuts' do
    it '.not_found returns Lux::Error with status 404' do
      err = Lux.error.not_found('missing')
      _(err).must_be_instance_of Lux::Error
      _(err.message).must_equal 'missing'
      _(Lux.current.response.status).must_equal 404
    end

    it '.forbidden returns Lux::Error with status 403' do
      err = Lux.error.forbidden('nope')
      _(err.message).must_equal 'nope'
      _(Lux.current.response.status).must_equal 403
    end

    it '.bad_request returns Lux::Error with status 400' do
      err = Lux.error.bad_request('bad')
      _(err.message).must_equal 'bad'
      _(Lux.current.response.status).must_equal 400
    end

    it '.internal_server_error returns Lux::Error with status 500' do
      Lux.error.internal_server_error('boom')
      _(Lux.current.response.status).must_equal 500
    end

    it 'shortcut without message fills from Rack status name' do
      err = Lux.error.not_found
      _(err.message).must_equal 'Not Found'
    end

    it 'is raisable: raise Lux.error.not_found raises Lux::Error' do
      _{ raise Lux.error.not_found('x') }.must_raise Lux::Error
    end
  end

  describe '.log' do
    it 'always writes the formatted error to Lux.logger.error' do
      with_debug_mode(false) do
        with_error_log_buffer do |buf|
          error = StandardError.new('boom')
          error.set_backtrace(["#{Lux.root}/app/models/thing.rb:10:in `run'"])

          Lux.error.log(error)

          _(buf.string).must_include '[StandardError] boom'
          _(buf.string).must_include './app/models/thing.rb:10'
        end
      end
    end

    it 'writes app caller, error class, and message to Lux.log in debug mode' do
      with_debug_mode(true) do
        with_error_log_buffer do |buf|
          Lux.error.log(StandardError.new('boom'))

          _(buf.string).must_match(/ - StandardError: boom/)
        end
      end
    end

    it 'suppresses the screen log outside debug mode' do
      with_debug_mode(false) do
        with_error_log_buffer do |buf|
          Lux.error.log(StandardError.new('boom'))

          refute buf.string.match?(/ - StandardError: boom/)
          _(buf.string).must_include '[StandardError] boom'
        end
      end
    end

    it 'runs the custom logger hook with the error' do
      seen = []

      with_log_custom(proc { |error| seen << error }) do
        with_error_log_buffer do
          error = StandardError.new('boom')
          Lux.error.log(error)

          _(seen).must_equal [error]
        end
      end
    end

    it 'logs the same exception object only once' do
      seen = []

      with_debug_mode(true) do
        with_log_custom(proc { |error| seen << error }) do
          with_error_log_buffer do |buf|
            error = StandardError.new('boom')
            error.set_backtrace(["#{Lux.root}/app/models/thing.rb:10:in `run'"])

            Lux.error.log(error)
            Lux.error.log(error)

            _(buf.string.scan(/ - StandardError: boom/).length).must_equal 1
            _(buf.string.scan(/\[StandardError\] boom/).length).must_equal 1
            _(seen).must_equal [error]
          end
        end
      end
    end

    it 'logs different exception objects separately' do
      with_error_log_buffer do |buf|
        Lux.error.log(StandardError.new('one'))
        Lux.error.log(StandardError.new('two'))

        _(buf.string.scan(/\[StandardError\]/).length).must_equal 2
      end
    end

    it 'does not let custom logger failures escape' do
      with_log_custom(proc { |_error| raise 'custom failed' }) do
        with_error_log_buffer do |buf|
          Lux.error.log(StandardError.new('boom'))

          _(buf.string).must_include 'Lux.error.log_custom failed: RuntimeError: custom failed'
        end
      end
    end
  end
end
