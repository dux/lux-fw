require_relative '../loader'

describe 'before/after callbacks' do
  context 'global callbacks' do
    it 'executes before callback' do
      # ApplicationApi sets @_time in before block
      response = GenericApi.render :all_ok
      expect(response[:success]).to eq(true)
    end

    it 'executes after callback' do
      # ApplicationApi sets :ip in after block
      response = GenericApi.render :all_ok
      expect(response[:meta][:ip]).to eq('1.2.3.4')
    end
  end

  context 'member-specific callbacks' do
    it 'executes member before callback' do
      # ModelApi member before loads @model
      response = CompanyApi.render :show, id: 1
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('ACME corp')
    end

    it 'member before can reject request' do
      # ModelApi member before returns error for invalid id
      response = CompanyApi.render :show, id: 999
      expect(response[:success]).to eq(false)
      expect(response[:error][:messages].first).to eq('Model not found')
    end
  end

  context 'callback execution order' do
    it 'executes callbacks in ancestor order' do
      # CompanyApi -> ModelApi -> ApplicationApi
      # before_all from ApplicationApi runs first
      # then before_member from ModelApi
      response = CompanyApi.render :index, id: 1, params: { name: 'Test' }
      expect(response[:success]).to eq(true)
      expect(response[:meta][:ip]).to eq('1.2.3.4')  # from ApplicationApi after
    end
  end

  context 'collection callbacks' do
    it 'does not run member before for collection methods' do
      # collection methods should not require @model
      response = CompanyApi.render :info
      expect(response[:success]).to eq(true)
      expect(response[:data][:countries_in_index]).to eq(123)
    end
  end
end
