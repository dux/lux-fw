require 'spec_helper'

Lux.schema :user1, type: :foo do
  name
  email :email
end

Lux.schema :api1 do
  foo
  user  model: :user1
end

Lux.schema :api_dyn, type: :foo do
  foo
  dyn do
    name
    email :email
  end
end

describe Lux::Type::ModelType do
  describe 'DB schema access' do
    let(:opts) {
      {
        foo: 123,
        bar: 456,
        user: {
          name: 'Dux',
          is_admin: true
        }
      }
    }

    it 'gets valid schema' do
      opts[:user][:email] = 'dux.net.hr'
      validated = Lux.schema(:api1).validate(opts)
      expect(validated['user.email']).to include('missing')
    end

    it 'gets valid schema' do
      opts[:user][:email] = 'dux@net.hr'
      validated = Lux.schema(:api1).validate(opts)
      expect(validated.keys.length).to eq(0)
    end

    it 'gets errors' do
      validated = Lux.schema(:api1).validate({ user: { foo: 1 } })

      for key in [:foo, 'user.name', 'user.email']
        expect(validated[key]).to include('req')
      end
    end

    it 'parses dynamic attributes' do
      params = { dyn: {} }
      validated = Lux.schema(:api_dyn).validate(params)

      for key in [:foo, 'dyn.name', 'dyn.email']
        expect(validated[key]).to include('req')
      end

      params = {
        foo: 'bar',
        dyn: {
          name: 'dux',
          email: 'duxnet.hr',
        }
      }
      validated = Lux.schema(:api_dyn).validate(params)
      expect(validated['dyn.email']).to include('missing')

      params = {
        foo: 'bar',
        dyn: {
          name: 'dux',
          email: 'dux@net.hr',
        }
      }
      validated = Lux.schema(:api_dyn).validate(params)
      expect(validated.keys.length).to eq(0)
    end

    it 'gets types right' do
      expect(Lux.schema(type: :foo).sort).to eq(['ApiDyn', 'User1'])
      expect(Lux.schema(type: :baz)).to eq([])
    end
  end
end
