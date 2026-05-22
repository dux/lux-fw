require_relative '../loader'

describe 'params validation' do
  context 'existing param tests from GenericApi' do
    it 'passes required params' do
      response = GenericApi.render :param_test_2, params: { foo: 'test' }
      expect(response[:success]).to eq(true)
      expect(response[:data][:foo]).to eq('test')
    end

    it 'applies defaults for optional params' do
      response = GenericApi.render :param_test_2, params: { foo: 'test' }
      expect(response[:data][:abc]).to eq('baz')  # default value (coerced to string)
    end

    it 'allows overriding defaults' do
      response = GenericApi.render :param_test_2, params: { foo: 'test', abc: 'custom' }
      expect(response[:data][:abc]).to eq('custom')
    end

    it 'fails when required param missing' do
      response = GenericApi.render :param_test_2, params: { abc: 'value' }
      expect(response[:success]).to eq(false)
      expect(response[:error][:details][:foo]).to be_truthy
    end
  end

  context 'CompanyApi params' do
    it 'validates integer type' do
      opts = CompanyApi.opts
      expect(opts[:collection][:index][:params][:country_id][:type]).to eq(:integer)
    end

    it 'validates boolean type' do
      opts = CompanyApi.opts
      expect(opts[:collection][:index][:params][:is_active][:type]).to eq(:boolean)
    end

    it 'handles boolean false default in member params' do
      opts = CompanyApi.opts
      expect(opts[:member][:index][:params][:is_active][:default]).to eq(false)
    end
  end

  context 'UserApi email validation' do
    it 'rejects bad email in model' do
      response = UserApi.render.update(1, user: { name: 'Test', email: 'bad email' })
      expect(response[:success]).to eq(false)
    end

    it 'accepts good email in model' do
      response = UserApi.render.update(1, user: { name: 'Test', email: 'good@email.com' })
      expect(response[:success]).to eq(true)
    end
  end

  context 'array params' do
    it 'accepts Array type param' do
      opts = GenericApi.opts
      expect(opts[:collection][:list_labels][:params][:labels_dup][:type]).to eq(:label)
      expect(opts[:collection][:list_labels][:params][:labels_dup][:array]).to eq(true)
    end

    it 'accepts Set type param stored as array' do
      opts = GenericApi.opts
      expect(opts[:collection][:list_labels][:params][:labels_nodup][:type]).to eq(:label)
      expect(opts[:collection][:list_labels][:params][:labels_nodup][:array]).to eq(true)
    end
  end
end
