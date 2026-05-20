require_relative '../loader'

describe 'error handling with status codes' do
  context 'named errors' do
    it 'handles named error code 405' do
      response = GenericApi.render :get_money
      expect(response[:success]).to eq(false)
      expect(response[:error][:messages]).to include('$ not found')
      expect(response[:error][:messages]).to include('405')
    end
  end

  context 'unhandled errors' do
    it 'handles unhandled exception with rescue_from :all' do
      $no_error_print = true
      response = GenericApi.render :about
      $no_error_print = false
      expect(response[:success]).to eq(false)
      expect(response[:status]).to eq(500)
      expect(response[:error][:messages]).to include('Error happens')
    end
  end

  context 'response_error class method' do
    it 'generates error response from class method' do
      err = GenericApi.response_error('foo bar')
      expect(err[:success]).to eq(false)
      expect(err[:error][:messages]).to include('foo bar')
    end
  end

  context 'error status codes' do
    it 'defaults to 400 for regular errors' do
      response = UserApi.render.login(user: 'wrong', pass: 'wrong')
      expect(response[:success]).to eq(false)
      expect(response[:status]).to eq(400)
    end

    it 'returns 500 for unhandled exceptions' do
      $no_error_print = true
      response = GenericApi.render :about
      $no_error_print = false
      expect(response[:status]).to eq(500)
    end
  end

  context 'error details' do
    it 'includes field-level error details for param validation' do
      response = GenericApi.render :param_test_2, params: {}
      expect(response[:success]).to eq(false)
      expect(response[:error][:details][:foo]).to be_truthy
    end
  end
end
