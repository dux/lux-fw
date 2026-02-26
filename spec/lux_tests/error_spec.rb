require 'spec_helper'

describe Lux::Error do
  describe 'initialization' do
    it 'creates error with status code' do
      error = Lux::Error.new(404)
      expect(error.code).to eq(404)
      expect(error.message).to eq('Document Not Found')
    end

    it 'creates error with status code and custom message' do
      error = Lux::Error.new(403, 'Access denied')
      expect(error.code).to eq(403)
      expect(error.message).to eq('Access denied')
    end

    it 'defaults to 400 when no status code given' do
      error = Lux::Error.new('Something went wrong')
      expect(error.code).to eq(400)
      expect(error.message).to eq('Something went wrong')
    end

    it 'raises for invalid status code' do
      expect { Lux::Error.new(999) }.to raise_error(RuntimeError, /not found/)
    end

    it 'is a StandardError' do
      expect(Lux::Error.new(400)).to be_a(StandardError)
    end
  end

  describe '#name' do
    it 'returns the HTTP status name' do
      expect(Lux::Error.new(404).name).to eq('Document Not Found')
      expect(Lux::Error.new(500).name).to eq('Internal Server Error')
      expect(Lux::Error.new(200).name).to eq('OK')
    end
  end

  describe 'factory methods' do
    it '.not_found creates a 404 error' do
      error = Lux::Error.not_found('Page missing')
      expect(error).to be_a(Lux::Error)
      expect(error.code).to eq(404)
      expect(error.message).to eq('Page missing')
    end

    it '.not_found without message uses default name' do
      error = Lux::Error.not_found
      expect(error.code).to eq(404)
      expect(error.message).to eq('Document Not Found')
    end

    it '.forbidden creates a 403 error' do
      error = Lux::Error.forbidden('No access')
      expect(error.code).to eq(403)
      expect(error.message).to eq('No access')
    end

    it '.unauthorized creates a 401 error' do
      error = Lux::Error.unauthorized('Login required')
      expect(error.code).to eq(401)
      expect(error.message).to eq('Login required')
    end

    it '.bad_request creates a 400 error' do
      error = Lux::Error.bad_request('Invalid input')
      expect(error.code).to eq(400)
      expect(error.message).to eq('Invalid input')
    end

    it '.internal_server_error creates a 500 error' do
      error = Lux::Error.internal_server_error('Server broke')
      expect(error.code).to eq(500)
      expect(error.message).to eq('Server broke')
    end

    it '.not_implemented creates a 501 error' do
      error = Lux::Error.not_implemented
      expect(error.code).to eq(501)
    end

    it '.method_not_allowed creates a 405 error' do
      error = Lux::Error.method_not_allowed
      expect(error.code).to eq(405)
    end
  end

  describe 'CODE_LIST' do
    it 'contains all standard HTTP status ranges' do
      codes = Lux::Error::CODE_LIST.keys
      expect(codes.any? { |c| c >= 100 && c < 200 }).to be true  # 1xx
      expect(codes.any? { |c| c >= 200 && c < 300 }).to be true  # 2xx
      expect(codes.any? { |c| c >= 300 && c < 400 }).to be true  # 3xx
      expect(codes.any? { |c| c >= 400 && c < 500 }).to be true  # 4xx
      expect(codes.any? { |c| c >= 500 && c < 600 }).to be true  # 5xx
    end

    it 'every entry has a name' do
      Lux::Error::CODE_LIST.each do |code, data|
        expect(data[:name]).to be_a(String), "Code #{code} missing name"
        expect(data[:name]).not_to be_empty, "Code #{code} has empty name"
      end
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
      expect(lines[0]).to eq('[StandardError] test')
      expect(lines[1]).to start_with('  ./')   # indented local app line
      expect(lines[2]).to start_with('  /')    # indented global gem line
    end

    it 'returns message when no backtrace' do
      error = StandardError.new('test')
      expect(Lux::Error.format(error)).to eq(['no backtrace present'])
    end
  end


end
