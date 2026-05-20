require_relative '../loader'

describe Lux::Api do
  let!(:name) { 'acme gmbh' }

  context 'company' do
    it 'gets valid collection url' do
      response = CompanyApi.render.update(1, company: { name: name, address: 'nowhere 123' })
      expect(response[:data][:name]).to eq(name)
    end

    it 'strips out undefined fields' do
      response = CompanyApi.render.update(1, company: { name: name, not_defined: 'nowhere 123' })
      expect(response[:data][:name]).to eq(name)
      expect(response[:data][:address]).to eq(nil)
      expect(response[:data][:not_defined]).to eq(nil)
    end

    it 'allows alternative method define' do
      response = CompanyApi.render.foo(1, { bar: 3 })
      expect(response[:data]).to eq(9)
    end
  end

  context 'user' do
    it 'rejects bad email in user model' do
      response = UserApi.render.update(1, user: { name: name, email: 'bad email' })
      expect(response[:success]).to eq(false)
    end

    it 'passes with good email' do
      response = UserApi.render.update(1, user: { name: name, email: 'better@email.com' })
      expect(response[:success]).to eq(true)
    end
  end

  context 'parent - child' do
    it 'test collection' do
      response = UserApi.render.call_me_in_child
      expect(response[:data]).to eq(4690)
    end

    it 'test member' do
      response = UserApi.render.call_me_in_child(1)
      expect(response[:data]).to eq(2468)
    end
  end
end