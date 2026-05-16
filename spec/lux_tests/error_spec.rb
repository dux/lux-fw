require 'spec_helper'

describe Lux::Error do
  before { Lux::Current.new('http://testing') }

  describe 'as an exception class' do
    it 'is a StandardError with no HTTP knowledge' do
      err = Lux::Error.new('something broke')
      expect(err).to be_a(StandardError)
      expect(err.message).to eq('something broke')
      expect(err.respond_to?(:code)).to be false
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
      expect(result).to be_a(String)
      lines = result.split("\n")
      expect(lines[0]).to start_with('URL: ')   # request URL header
      expect(lines[1]).to eq('[StandardError] test')
      expect(lines[2]).to start_with('  ./')   # local app line
      expect(lines[3]).to start_with('  /')    # gem line
    end

    it 'returns array marker when no backtrace' do
      error = StandardError.new('test')
      expect(Lux::Error.format(error)).to eq(['no backtrace present'])
    end
  end
end

describe 'Lux.error' do
  before { Lux::Current.new('http://testing') }

  describe 'with integer code' do
    it 'raises Lux::Error and sets response status to that code' do
      expect { Lux.error 404 }.to raise_error(Lux::Error)
      expect(Lux.current.response.status).to eq(404)
    end

    it 'fills the message from Rack::Utils::HTTP_STATUS_CODES when none given' do
      err = (Lux.error 404 rescue $!)
      expect(err.message).to eq('Not Found')
    end

    it 'uses the custom message when provided' do
      err = (Lux.error 404, 'missing thing' rescue $!)
      expect(err.message).to eq('missing thing')
      expect(Lux.current.response.status).to eq(404)
    end
  end

  describe 'with message only (no code)' do
    it 'defaults to status 400 and uses the given message' do
      err = (Lux.error 'oops' rescue $!)
      expect(err.message).to eq('oops')
      expect(Lux.current.response.status).to eq(400)
    end
  end

  describe 'with no args' do
    it 'returns the ErrorProxy for chained shortcuts' do
      expect(Lux.error).to be(Lux::ErrorProxy)
    end
  end

  describe 'proxy shortcuts' do
    it '.not_found raises with status 404' do
      err = (Lux.error.not_found('missing') rescue $!)
      expect(err.message).to eq('missing')
      expect(Lux.current.response.status).to eq(404)
    end

    it '.forbidden raises with status 403' do
      err = (Lux.error.forbidden('nope') rescue $!)
      expect(err.message).to eq('nope')
      expect(Lux.current.response.status).to eq(403)
    end

    it '.bad_request raises with status 400' do
      err = (Lux.error.bad_request('bad') rescue $!)
      expect(err.message).to eq('bad')
      expect(Lux.current.response.status).to eq(400)
    end

    it '.internal_server_error raises with status 500' do
      err = (Lux.error.internal_server_error('boom') rescue $!)
      expect(Lux.current.response.status).to eq(500)
    end

    it 'shortcut without message fills from Rack status name' do
      err = (Lux.error.not_found rescue $!)
      expect(err.message).to eq('Not Found')
    end
  end
end
