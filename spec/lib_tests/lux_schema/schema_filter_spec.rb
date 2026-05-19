require 'spec_helper'

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
      expect(schema.rules.keys).to eq([:name, :email])
    end

    it 'returns a Schema instance' do
      expect(FilterSchema.only(:name)).to be_a(Lux::Schema)
    end

    it 'ignores non-existent keys' do
      schema = FilterSchema.only(:name, :nonexistent)
      expect(schema.rules.keys).to eq([:name])
    end

    it 'returns empty schema when no keys match' do
      schema = FilterSchema.only(:nonexistent)
      expect(schema.rules.keys).to eq([])
    end

    it 'accepts string keys' do
      schema = FilterSchema.only('name', 'email')
      expect(schema.rules.keys).to eq([:name, :email])
    end
  end

  describe '#except' do
    it 'returns schema without specified keys' do
      schema = FilterSchema.except(:age, :is_active)
      expect(schema.rules.keys).to eq([:name, :email])
    end

    it 'returns a Schema instance' do
      expect(FilterSchema.except(:name)).to be_a(Lux::Schema)
    end

    it 'ignores non-existent keys' do
      schema = FilterSchema.except(:nonexistent)
      expect(schema.rules.keys).to eq([:name, :email, :age, :is_active])
    end

    it 'accepts string keys' do
      schema = FilterSchema.except('age', 'is_active')
      expect(schema.rules.keys).to eq([:name, :email])
    end
  end

  describe 'chaining' do
    it 'chains except then only' do
      schema = FilterSchema.except(:is_active).only(:name, :email)
      expect(schema.rules.keys).to eq([:name, :email])
    end

    it 'chains only then except' do
      schema = FilterSchema.only(:name, :email, :age).except(:age)
      expect(schema.rules.keys).to eq([:name, :email])
    end
  end

  describe 'validation on filtered schema' do
    it 'validates included fields' do
      schema = FilterSchema.only(:name, :email)
      data = { name: 'Dux', email: 'dux@example.com' }
      errors = schema.validate data
      expect(errors).to eq({})
    end

    it 'reports errors for required included fields' do
      schema = FilterSchema.only(:name, :email)
      data = { name: 'Dux' }
      errors = schema.validate data
      expect(errors[:email]).to be_truthy
    end

    it 'does not report errors for excluded required fields' do
      schema = FilterSchema.only(:name)
      data = { name: 'Dux' }
      errors = schema.validate data
      expect(errors).to eq({})
    end

    it 'applies defaults on filtered schema' do
      schema = FilterSchema.only(:name, :age)
      data = { name: 'Dux' }
      schema.validate data
      expect(data[:age]).to eq(21)
    end

    it 'valid? works on filtered schema' do
      schema = FilterSchema.only(:name)
      expect(schema.valid?({ name: 'Dux' })).to eq(true)
      expect(schema.valid?({})).to eq(false)
    end
  end

  describe 'preserves field options' do
    it 'keeps type and defaults' do
      schema = FilterSchema.only(:age, :is_active)
      expect(schema.rules[:age][:type]).to eq(:integer)
      expect(schema.rules[:age][:default]).to eq(21)
      expect(schema.rules[:is_active][:type]).to eq(:boolean)
      expect(schema.rules[:is_active][:default]).to eq(false)
    end
  end

  describe 'nested model fields' do
    it 'works with only on nested field' do
      schema = FilterNestedSchema.only(:name, :settings)
      expect(schema.rules.keys).to eq([:name, :settings])
      expect(schema.rules[:settings][:type]).to eq(:model)
    end

    it 'works with except on nested field' do
      schema = FilterNestedSchema.except(:settings)
      expect(schema.rules.keys).to eq([:name])
    end

    it 'validates nested field after filter' do
      schema = FilterNestedSchema.only(:settings)
      data = { settings: { theme: 'dark' } }
      errors = schema.validate data
      expect(errors).to eq({})
      expect(data[:settings][:lang]).to eq('en')
    end
  end

  describe 'does not mutate original' do
    it 'leaves original schema unchanged' do
      original_keys = FilterSchema.rules.keys.dup
      FilterSchema.only(:name)
      FilterSchema.except(:name)
      expect(FilterSchema.rules.keys).to eq(original_keys)
    end
  end
end
