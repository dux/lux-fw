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
end
