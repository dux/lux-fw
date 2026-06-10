require 'test_helper'
require_relative './fixtures'

describe Lux::Schema do
  def rules
    @rules ||= TestSchema
  end

  describe 'DB schema access' do
    it 'gets valid schema' do
      schema = rules.db_schema
      _(schema[0]).must_equal [:name, :string, { limit: 255 }]
      _(schema[1]).must_equal [:speed, :float, {}]
      _(schema[2]).must_equal [:email, :string, { limit: 120, null: false }]
      _(schema[3]).must_equal [:email_nil, :string, { limit: 120 }]
      _(schema[4]).must_equal [:emails, :string, { array: true, limit: 120 }]
      _(schema[5]).must_equal [:tags, :string, { array: true, limit: 30 }]
      _(schema[6]).must_equal [:eyes, :string, { default: 'blue', limit: 255, null: false }]
      _(schema[7]).must_equal [:age, :integer, { null: false }]
      _(schema.length).must_equal 13
    end

    it 'gets db_rules separately' do
      db_rules = rules.db_rules
      _(db_rules).must_equal [[:timestamps]]
    end
  end

  describe 'virtual fields' do
    VirtualSchema ||= Lux.schema do
      name
      full_name virtual: true
    end

    it 'keeps virtual fields in rules but excludes them from db_schema' do
      _(VirtualSchema.rules.key?(:full_name)).must_equal true
      _(VirtualSchema.db_schema.map(&:first)).wont_include :full_name
      _(VirtualSchema.db_schema.map(&:first)).must_include :name
    end

    it 'still validates/coerces a virtual field' do
      data = { name: 'a', full_name: 123 }
      VirtualSchema.validate(data)
      _(data[:full_name]).must_equal '123'   # coerced to string
    end
  end
end
