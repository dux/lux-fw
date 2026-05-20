require_relative '../loader'
require_relative '../../lib/joshua/client'

module HTTP
  def self.post url, opts=nil
    {
      url: url,
      opts: opts
    }.to_json
  end
end

describe 'dev' do
  let (:api) { JoshuaClient.new 'http://localhost:4567/api' }

  it 'gets valid collection url' do
    data = api.user.login
    expect(data['url']).to eq('http://localhost:4567/api/user/login')
    expect(data['opts']['form'].keys.length).to eq(0)
  end

  it 'gets valid url with params' do
    data = api.admin__user.login user: 'foo', pass: 'bar'
    expect(data['url']).to eq('http://localhost:4567/api/admin__user/login')
    expect(data['opts']['form'].keys.length).to eq(2)
  end

  it 'gets valid url with id and params' do
    data = api.user(123).show user: 'foo', pass: 'bar'
    expect(data['url']).to eq('http://localhost:4567/api/user/123/show')
    expect(data['opts']['form'].keys.length).to eq(2)
  end
end