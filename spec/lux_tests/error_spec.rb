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

    it 'returns array marker when no backtrace' do
      error = StandardError.new('test')
      _(Lux::Error.format(error)).must_equal ['no backtrace present']
    end
  end
end

describe 'Lux.error' do
  before { Lux::Current.new('http://testing') }

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
end
