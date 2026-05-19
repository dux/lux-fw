require 'spec_helper'
require_relative './fixtures'

describe Lux::Schema do
  before(:all) do
    @rules = TestSchema
  end

  describe 'DB schema access' do
    it 'gets valid schema' do
      schema = @rules.db_schema
      expect(schema[0]).to eq([:name, :string, { limit: 255 }])
      expect(schema[1]).to eq([:speed, :float, {}])
      expect(schema[2]).to eq([:email, :string, { limit: 120, null: false }])
      expect(schema[3]).to eq([:email_nil, :string, { limit: 120 }])
      expect(schema[4]).to eq([:emails, :string, { array: true, limit: 120 }])
      expect(schema[5]).to eq([:tags, :string, { array: true, limit: 30 }])
      expect(schema[6]).to eq([:eyes, :string, { default: 'blue', limit: 255, null: false }])
      expect(schema[7]).to eq([:age, :integer, { null: false }])
      expect(schema.length).to eq(13)
    end

    it 'gets db_rules separately' do
      db_rules = @rules.db_rules
      expect(db_rules).to eq([[:timestamps]])
    end
  end
end
