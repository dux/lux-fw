require 'test_helper'

describe 'clean hash' do
  describe 'default mode' do
    def h_default
      @h_default ||= {
        a1: {
          'a2' => {
            a3: :a3_foo,
            b3: true
          }
        },
        b1: {
          'b2' => :b2_foo
        }
      }.to_lux_hash
    end

    it 'works like hashie mash' do
      _(h_default.a1.a2.a3).must_equal :a3_foo
      _(h_default[:a1]['a2'].a3).must_equal :a3_foo
    end

    it 'raises error when accessing as method for key not found' do
      _{ h_default.a1.not_found_ }.must_raise NoMethodError
    end

    it 'returns list keys and values' do
      _(h_default.a1.a2.keys).must_equal ['a3', 'b3']
      _(h_default.a1.a2.values).must_equal [:a3_foo, true]
    end

    it 'can set deep value' do
      base = h_default
      base.a1.a2.a3 = :foo
      _(base.a1.a2.a3).must_equal :foo
    end

    it 'can set all type of keys' do
      h = {}.to_lux_hash
      h[:foo1]  = :foo1
      h['foo2'] = :foo2
      h.foo3    = :foo3

      _(h[:foo1]).must_equal :foo1
      _(h[:foo2]).must_equal :foo2
      _(h[:foo3]).must_equal :foo3
    end

    it 'uses string key as a default' do
      h = {}.to_lux_hash
      h[:foo]  = { :bar => :symbol, 'bar' => 'string' }
      _(h.foo.bar).must_equal 'string'
      _(h[:foo]['bar']).must_equal 'string'
    end

    it 'allows weird key' do
      name  = 'a?#b'
      value = :value

      h = {}.to_lux_hash
      h[name] = value

      _(h[name]).must_equal value
    end

    it 'it allows special key name' do
      h = { foo: :bar, keys: :baz, size: 453, length: 'foo' }.to_lux_hash

      _(h.keys).must_equal ['foo', 'keys', 'size', 'length']
      _(h[:keys]).must_equal :baz
      _(h['keys']).must_equal :baz

      _(h.size).must_equal 453
      _(h[:size]).must_equal 453

      _(h.length).must_equal 'foo'
      _(h['length']).must_equal 'foo'

      _(h.keys.length).must_equal 4
    end

    it 'can add proc to hash' do
      h = {}.to_lux_hash
      h.proc_test do |num|
        num * 123
      end

      _(h.proc_test.call(2)).must_equal 246
    end

    it 'responds to each' do
      data = []

      for k, v in h_default
        data.push k
      end

      _(data).must_equal %w(a1 b1)
    end

    it 'each yields right class' do
      data = {
        a: {
          b: {
            c: 1
          }
        }
      }.to_lux_hash

      for k, v in data
        _(v.b.c).must_equal 1
      end
    end

    it 'each works on list of hashes' do
      data = {
        a: {
          b: [{
            foo: 123
          }]
        }
      }.to_lux_hash

      for el in data.a.b
        _(el.foo).must_equal 123
      end
    end

    it 'deletes a key' do
      h = h_default

      h[Hash] = 123

      _(h[:a1][:a2].delete(:a3)).must_equal :a3_foo
      _(h[:a1][:a2].delete(:a3)).must_be_nil
      _(h[:a1][:a2][:a3]).must_be_nil
      _(h.delete(Hash)).must_equal 123
      _(h[Hash]).must_be_nil
    end

    it 'can delete keys' do
      h = { :foo => :bar, bar: :baz }.to_lux_hash
      _(h[:foo]).must_equal :bar
      h.delete(:foo)
      _(h[:foo]).must_be_nil

      _(h[:bar]).must_equal :baz
      h.delete('bar')
      _(h[:bar]).must_be_nil
      _(h['bar']).must_be_nil
    end

    it 'can access complex keys' do
      h = { 123 => :foo, String => :bar }.to_lux_hash

      _(h[123]).must_equal :foo
      _(h[String]).must_equal :bar
    end

    it 'can add keys' do
      h = { :foo => :bar, String => :bar }.to_lux_hash
      h[:bar] = {}
      h[:bar][:baz] = 123

      _(h.bar.baz).must_equal 123
      _(h[:bar].baz).must_equal 123
      _(h.bar[:baz]).must_equal 123
    end

    it 'can merge' do
      h  = { foo: :bar }.to_lux_hash
      nh = h.merge(foo: { jaz: :baz})

      _(h.foo).must_equal :bar
      _(nh.foo.jaz).must_equal :baz

      h.merge!(foo: { jaz: :baz})

      _(h.foo.jaz).must_equal :baz
    end

    it 'deletes key on method set' do
      h = {}.to_lux_hash
      h[:foo] = 123
      h.foo = 456
      _(h.foo).must_equal 456
      _(h[:foo]).must_equal 456
      _(h['foo']).must_equal 456
    end

    it 'coerces all keys to string' do
      h = {}.to_lux_hash
      h[123] = 456
      _(h[123]).must_equal 456
      _(h['123']).must_equal 456
      _(h.keys).must_equal ['123']
    end

    it 'raises on nil or empty key on write' do
      h = {}.to_lux_hash
      _{ h[nil] = 1 }.must_raise ArgumentError
      _{ h[''] = 1 }.must_raise ArgumentError
    end

    it 'returns nil on nil-key read (does not raise)' do
      h = {}.to_lux_hash
      _(h[nil]).must_be_nil
      _(h['']).must_be_nil
    end

    it 'key? / fetch / delete coerce keys' do
      h = {}.to_lux_hash
      h[123] = :x
      _(h.key?(123)).must_equal true
      _(h.key?('123')).must_equal true
      _(h.fetch(123)).must_equal :x
      _(h.fetch('123')).must_equal :x
      _(h.delete(123)).must_equal :x
      _(h.key?('123')).must_equal false
    end

    it 'returns nested hash with Lux::Hash::Methods' do
      h1 = {
        foo: {
          bar: :baz
        }
      }.to_lux_hash

      h2 = h1[:foo]
      _(h2.is_a?(Lux::Hash::Methods)).must_equal true
    end

    it 'can push to array' do
      h = {foo: []}.to_lux_hash
      h[:foo].push 1
      h.foo.push 2
      _(h.foo).must_equal [1, 2]
    end
  end
end
