require 'spec_helper'

Lux.schema(:cache) do
  name
end

FuncSchema ||= Lux.schema do
  name

  integer! do
    num
    labels Set[:label]
  end

  false! do
    is_active
  end
end

BareArraySchema ||= Lux.schema do
  tags Array
  items Set
end

describe Lux do
  describe 'Func access' do
    it 'can create schema' do
      expect(FuncSchema.rules[:name][:type]).to eq(:string)
    end

    it 'it can set and access the schema' do
      expect(Lux.schema(:cache).rules[:name][:type]).to eq(:string)
    end

    it 'it can access the class stype schema' do
      expect(FuncSchema.rules[:name][:type]).to eq(:string)
    end

    it 'can defined nested schema' do
      s = FuncSchema.rules
      expect(s[:num][:type]).to eq(:integer)
      expect(s[:num][:required]).to eq(true)
      expect(s[:labels][:required]).to eq(true)
      expect(s[:labels][:array]).to eq(true)
      expect(s[:labels][:type]).to eq(:integer)
      expect(s[:is_active][:type]).to eq(:boolean)
    end

    it 'supports bare Array as type (array of strings)' do
      s = BareArraySchema.rules
      expect(s[:tags][:type]).to eq(:string)
      expect(s[:tags][:array]).to eq(true)
    end

    it 'supports bare Set as type (array of strings)' do
      s = BareArraySchema.rules
      expect(s[:items][:type]).to eq(:string)
      expect(s[:items][:array]).to eq(true)
    end

    it 'validates bare Array field values' do
      data = { tags: ['foo', 'bar'], items: ['a', 'b'] }
      errors = BareArraySchema.validate(data)
      expect(errors).to be_empty
      expect(data[:tags]).to eq(['foo', 'bar'])
    end

    it 'deduplicates bare Array field values by default' do
      data = { tags: ['foo', 'foo', 'bar'], items: ['a', 'b'] }
      BareArraySchema.validate(data)
      expect(data[:tags]).to eq(['foo', 'bar'])
    end
  end
end
