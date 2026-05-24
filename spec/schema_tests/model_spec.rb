require 'test_helper'

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
    def opts
      @opts ||= {
        foo: 123,
        bar: 456,
        user: {
          name: 'Dux',
          is_admin: true
        }
      }
    end

    it 'gets valid schema' do
      opts[:user][:email] = 'dux.net.hr'
      validated = Lux.schema(:api1).validate(opts)
      _(validated['user.email']).must_include 'missing'
    end

    it 'gets valid schema' do
      opts[:user][:email] = 'dux@net.hr'
      validated = Lux.schema(:api1).validate(opts)
      _(validated.keys.length).must_equal 0
    end

    it 'gets errors' do
      validated = Lux.schema(:api1).validate({ user: { foo: 1 } })

      for key in [:foo, 'user.name', 'user.email']
        _(validated[key]).must_include 'req'
      end
    end

    it 'parses dynamic attributes' do
      params = { dyn: {} }
      validated = Lux.schema(:api_dyn).validate(params)

      for key in [:foo, 'dyn.name', 'dyn.email']
        _(validated[key]).must_include 'req'
      end

      params = {
        foo: 'bar',
        dyn: {
          name: 'dux',
          email: 'duxnet.hr',
        }
      }
      validated = Lux.schema(:api_dyn).validate(params)
      _(validated['dyn.email']).must_include 'missing'

      params = {
        foo: 'bar',
        dyn: {
          name: 'dux',
          email: 'dux@net.hr',
        }
      }
      validated = Lux.schema(:api_dyn).validate(params)
      _(validated.keys.length).must_equal 0
    end

    it 'gets types right' do
      _(Lux.schema(type: :foo).sort).must_equal ['ApiDyn', 'User1']
      _(Lux.schema(type: :baz)).must_equal []
    end
  end
end
