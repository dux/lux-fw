require 'test_helper'
require_relative '../loader'

describe 'dev' do
  def opts
    @opts ||= CompanyApi.opts
  end

  it 'tests valid collection methods params' do
    _(opts.dig(:collection, :index, :params, :country_id, :type)).must_equal :integer
    _(opts.dig(:collection, :index, :params, :is_active, :type)).must_equal :boolean
    _(opts.dig(:collection, :info)).must_equal({})
  end

  it 'tests valid mememer methods params' do
    _(opts.dig(:member, :index, :params, :is_active)).must_equal({ type: :boolean, required: false, default: false })
    _(opts.dig(:member, :show)).must_equal({})
  end

  it 'tests valid deep method defines (from parent ModelApi)' do
    _(opts.dig(:member, :creator, :params)).must_equal({ show_all: { type: :boolean, required: false, default: false } })
  end

  it 'adds method descriptions' do
    _(opts.dig(:member, :index, :desc)).must_equal('Simple index')
    _(opts.dig(:member, :creator, :desc).length).must_equal(21)
  end

  it 'executes before in order' do
    response = CompanyApi.render :index, id: 1, params: { name: 'Dux' }
    _(response).must_equal({success: true, message: 'all ok', meta: { ip: '1.2.3.4' }, data: 'ACME corp', status: 200 })
  end

  it 'expects clasic module to be incuded' do
    response = GenericApi.render :module_clasic
    _(response).must_equal({ data: 'is_module', meta: { ip: '1.2.3.4' }, success: true, status: 200})
  end

  it 'expects plugins to work' do
    response = GenericApi.render :plugin_test
    _(response).must_equal({ data: 'from_plugin', success: true, status: 200, meta: { ip: '1.2.3.4' }})
  end

  it 'expects csv as a response' do
    response = GenericApi.render :send_csv
    _(response.split($/).first).must_equal('name;email')
  end

  it 'logs in success' do
    response = UserApi.render.login user: 'foo', pass: 'bar'
    _(response[:success]).must_equal(true)
  end

  it 'defines allowed method' do
    _(UserApi.opts.dig(:collection, :call_me_in_child, :allow)).must_equal ['DELETE']
  end

  it 'extracts bearer token from Authorization header' do
    token = Lux::Api.send(:extract_bearer_token, 'Bearer my-token')
    _(token).must_equal('my-token')
  end

  it 'returns nil for invalid bearer token header' do
    token = Lux::Api.send(:extract_bearer_token, 'Basic invalid')
    _(token).must_be_nil
  end

  it 'returns nil for nil header' do
    token = Lux::Api.send(:extract_bearer_token, nil)
    _(token).must_be_nil
  end

  it 'accepts Symbol in content_type' do
    class TestContentTypeApi < Lux::Api
      content_type :json
    end
    refute_nil TestContentTypeApi
  end
end
