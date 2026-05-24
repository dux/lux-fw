require 'test_helper'

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
      _(FuncSchema.rules[:name][:type]).must_equal :string
    end

    it 'it can set and access the schema' do
      _(Lux.schema(:cache).rules[:name][:type]).must_equal :string
    end

    it 'it can access the class stype schema' do
      _(FuncSchema.rules[:name][:type]).must_equal :string
    end

    it 'can defined nested schema' do
      s = FuncSchema.rules
      _(s[:num][:type]).must_equal :integer
      _(s[:num][:required]).must_equal true
      _(s[:labels][:required]).must_equal true
      _(s[:labels][:array]).must_equal true
      _(s[:labels][:type]).must_equal :integer
      _(s[:is_active][:type]).must_equal :boolean
    end

    it 'supports bare Array as type (array of strings)' do
      s = BareArraySchema.rules
      _(s[:tags][:type]).must_equal :string
      _(s[:tags][:array]).must_equal true
    end

    it 'supports bare Set as type (array of strings)' do
      s = BareArraySchema.rules
      _(s[:items][:type]).must_equal :string
      _(s[:items][:array]).must_equal true
    end

    it 'validates bare Array field values' do
      data = { tags: ['foo', 'bar'], items: ['a', 'b'] }
      errors = BareArraySchema.validate(data)
      assert_empty errors
      _(data[:tags]).must_equal ['foo', 'bar']
    end

    it 'deduplicates bare Array field values by default' do
      data = { tags: ['foo', 'foo', 'bar'], items: ['a', 'b'] }
      BareArraySchema.validate(data)
      _(data[:tags]).must_equal ['foo', 'bar']
    end
  end
end
