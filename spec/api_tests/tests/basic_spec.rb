require_relative '../loader'

describe 'dev' do
  let (:opts) { CompanyApi.opts }

  it 'tests valid collection methods params' do
    expect(opts.dig(:collection, :index, :params, :country_id, :type)).to eq :integer
    expect(opts.dig(:collection, :index, :params, :is_active, :type)).to eq :boolean
    expect(opts.dig(:collection, :info)).to eq({})
  end

  it 'tests valid mememer methods params' do
    expect(opts.dig(:member, :index, :params, :is_active)).to eq({ type: :boolean, default: false, required: true })
    expect(opts.dig(:member, :show)).to eq({})
  end

  it 'tests valid deep method defines (from parent ModelApi)' do
    expect(opts.dig(:member, :creator, :params)).to eq({:show_all=>{:default=>false, :type=>:boolean, :required=>true}})
  end

  it 'adds method descriptions' do
    expect(opts.dig(:member, :index, :desc)).to eq('Simple index')
    expect(opts.dig(:member, :creator, :desc).length).to eq(21)
  end

  it 'executes before in order' do
    response = CompanyApi.render :index, id: 1, params: { name: 'Dux' }
    expect(response).to eq({success: true, message: 'all ok', meta: { ip: '1.2.3.4' }, data: 'ACME corp', status: 200 })
  end

  it 'expects clasic module to be incuded' do
    response = GenericApi.render :module_clasic
    expect(response).to eq({ data: 'is_module', meta: { ip: '1.2.3.4' }, success: true, status: 200})
  end

  it 'expects plugins to work' do
    response = GenericApi.render :plugin_test
    expect(response).to eq({ data: 'from_plugin', success: true, status: 200, meta: { ip: '1.2.3.4' }})
  end

  it 'expects csv as a response' do
    response = GenericApi.render :send_csv
    expect(response.split($/).first).to eq('name;email')
  end

  it 'logs in success' do
    response = UserApi.render.login user: 'foo', pass: 'bar'
    expect(response[:success]).to eq(true)
  end

  it 'defines allowed method' do
    expect(UserApi.opts.dig(:collection, :call_me_in_child, :allow)).to eq ['DELETE']
  end

  it 'extracts bearer token from Authorization header' do
    token = Lux::Api.send(:extract_bearer_token, 'Bearer my-token')
    expect(token).to eq('my-token')
  end

  it 'returns nil for invalid bearer token header' do
    token = Lux::Api.send(:extract_bearer_token, 'Basic invalid')
    expect(token).to be_nil
  end

  it 'returns nil for nil header' do
    token = Lux::Api.send(:extract_bearer_token, nil)
    expect(token).to be_nil
  end

  it 'accepts Symbol in content_type' do
    class TestContentTypeApi < Lux::Api
      content_type :json
    end
    expect(TestContentTypeApi).not_to be_nil
  end
end
