require_relative '../loader'

describe 'dev' do
  it 'calls login trough proxy' do
    response = UserApi.render.login(user: 'foo', pass: 'bar')
    expect(response[:success]).to eq(true)
  end

  it 'calls login trough proxy' do
    response = CompanyApi.render.show(1)
    expect(response[:success]).to eq(true)
    expect(response[:data]).to eq('ACME corp')
  end
end
