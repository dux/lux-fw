require 'test_helper'

FilterSchema ||= Lux.schema do
  name
  email :email
  age Integer, default: 21
  is_active false
end

FilterNestedSchema ||= Lux.schema do
  name
  settings do
    theme
    lang default: 'en'
  end
end

describe Lux::Schema do
  describe '#only' do
    it 'returns schema with only specified keys' do
      schema = FilterSchema.only(:name, :email)
      _(schema.rules.keys).must_equal [:name, :email]
    end

    it 'returns a Schema instance' do
      _(FilterSchema.only(:name)).must_be_kind_of Lux::Schema
    end

    it 'ignores non-existent keys' do
      schema = FilterSchema.only(:name, :nonexistent)
      _(schema.rules.keys).must_equal [:name]
    end

    it 'returns empty schema when no keys match' do
      schema = FilterSchema.only(:nonexistent)
      _(schema.rules.keys).must_equal []
    end

    it 'accepts string keys' do
      schema = FilterSchema.only('name', 'email')
      _(schema.rules.keys).must_equal [:name, :email]
    end
  end

  describe '#except' do
    it 'returns schema without specified keys' do
      schema = FilterSchema.except(:age, :is_active)
      _(schema.rules.keys).must_equal [:name, :email]
    end

    it 'returns a Schema instance' do
      _(FilterSchema.except(:name)).must_be_kind_of Lux::Schema
    end

    it 'ignores non-existent keys' do
      schema = FilterSchema.except(:nonexistent)
      _(schema.rules.keys).must_equal [:name, :email, :age, :is_active]
    end

    it 'accepts string keys' do
      schema = FilterSchema.except('age', 'is_active')
      _(schema.rules.keys).must_equal [:name, :email]
    end
  end

  describe 'chaining' do
    it 'chains except then only' do
      schema = FilterSchema.except(:is_active).only(:name, :email)
      _(schema.rules.keys).must_equal [:name, :email]
    end

    it 'chains only then except' do
      schema = FilterSchema.only(:name, :email, :age).except(:age)
      _(schema.rules.keys).must_equal [:name, :email]
    end
  end

  describe 'validation on filtered schema' do
    it 'validates included fields' do
      schema = FilterSchema.only(:name, :email)
      data = { name: 'Dux', email: 'dux@example.com' }
      errors = schema.validate data
      _(errors).must_equal({})
    end

    it 'reports errors for required included fields' do
      schema = FilterSchema.only(:name, :email)
      data = { name: 'Dux' }
      errors = schema.validate data
      _(errors[:email]).wont_be_nil
    end

    it 'does not report errors for excluded required fields' do
      schema = FilterSchema.only(:name)
      data = { name: 'Dux' }
      errors = schema.validate data
      _(errors).must_equal({})
    end

    it 'applies defaults on filtered schema' do
      schema = FilterSchema.only(:name, :age)
      data = { name: 'Dux' }
      schema.validate data
      _(data[:age]).must_equal 21
    end

    it 'valid? works on filtered schema' do
      schema = FilterSchema.only(:name)
      _(schema.valid?({ name: 'Dux' })).must_equal true
      _(schema.valid?({})).must_equal false
    end
  end

  describe 'preserves field options' do
    it 'keeps type and defaults' do
      schema = FilterSchema.only(:age, :is_active)
      _(schema.rules[:age][:type]).must_equal :integer
      _(schema.rules[:age][:default]).must_equal 21
      _(schema.rules[:is_active][:type]).must_equal :boolean
      _(schema.rules[:is_active][:default]).must_equal false
    end
  end

  describe 'nested model fields' do
    it 'works with only on nested field' do
      schema = FilterNestedSchema.only(:name, :settings)
      _(schema.rules.keys).must_equal [:name, :settings]
      _(schema.rules[:settings][:type]).must_equal :model
    end

    it 'works with except on nested field' do
      schema = FilterNestedSchema.except(:settings)
      _(schema.rules.keys).must_equal [:name]
    end

    it 'validates nested field after filter' do
      schema = FilterNestedSchema.only(:settings)
      data = { settings: { theme: 'dark' } }
      errors = schema.validate data
      _(errors).must_equal({})
      _(data[:settings][:lang]).must_equal 'en'
    end
  end

  describe 'does not mutate original' do
    it 'leaves original schema unchanged' do
      original_keys = FilterSchema.rules.keys.dup
      FilterSchema.only(:name)
      FilterSchema.except(:name)
      _(FilterSchema.rules.keys).must_equal original_keys
    end
  end
end
