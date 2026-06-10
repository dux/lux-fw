require 'test_helper'

NestedSchema1 ||= Lux.schema do
  foo
  bar do
    baz Integer, default: 123
    name
  end
end

SimpleSchema ||= Lux.schema do
  name
  age Integer, default: 21
end

NestedSchema2 ||= Lux.schema do
  foo
  bar SimpleSchema
end

describe Lux do
  describe NestedSchema1 do
    def data
      @data ||= {
        foo: 'exists',
        bar: {
          'name' => 'Dux',
          country: 'croatia'
        }
      }
    end

    it 'filters as expected' do
      valid = {
        foo: 'exists',
        bar: {
          name: 'Dux',
          baz: 123
        }
      }

      errors = NestedSchema1.validate data
      _(errors).must_equal({})
      _(data).must_equal(valid)
    end
  end

  describe NestedSchema2 do
    def data
      @data ||= {
        foo: 'exists',
        bar: {
          name: 'Dux',
          country: 'croatia'
        }
      }
    end

    it 'filters as expected' do
      valid = {
        foo: 'exists',
        bar: {
          name: 'Dux',
          age: 21
        }
      }

      errors = NestedSchema2.validate data
      _(errors).must_equal({})
      _(data).must_equal(valid)
    end
  end

  # a model-backed nested field validates against the model's api_schema (audit
  # columns excluded) and skips required (values live on the row). Ad-hoc nested
  # schemas without a backing model still enforce required - see model_spec.rb.
  describe 'model-backed nested field' do
    # stand-in for a Sequel model: exposes api_schema and is tagged as the
    # nested schema's model_klass, the same wiring lux_schema does on real models
    class FakeModel
      def self.api_schema
        Lux.schema('full_user_x').except(:created_at, :updated_at, :creator_ref, :updater_ref)
      end
    end

    FullUserX ||= Lux.schema 'full_user_x', type: :model do
      name
      created_at :datetime
      updated_at :datetime
      creator_ref
      updater_ref
    end
    FullUserX.model_klass = FakeModel

    NestedModelSchema ||= Lux.schema do
      user model: 'full_user_x'
    end

    it 'drops audit fields and does not require model-backed nested input' do
      errors = NestedModelSchema.validate(user: { name: 'Dux' })
      _(errors).must_equal({})
    end

    it 'strips audit keys sent by the client' do
      data = { user: { name: 'Dux', created_at: '2020-01-01' } }
      NestedModelSchema.validate(data)
      _(data[:user].key?(:created_at)).must_equal false
    end
  end
end
