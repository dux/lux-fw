require 'spec_helper'

describe 'clean hash' do
  context 'default mode' do
    let(:h_default) do
      {
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
      expect(h_default.a1.a2.a3).to eq(:a3_foo)
      expect(h_default[:a1]['a2'].a3).to eq(:a3_foo)
    end

    it 'raises error when accessing as method for key not found' do
      expect { h_default.a1.not_found_}.to raise_error NoMethodError
    end

    it 'returns list keys and values' do
      expect(h_default.a1.a2.keys).to eq(['a3', 'b3'])
      expect(h_default.a1.a2.values).to eq([:a3_foo, true])
    end

    it 'can set deep value' do
      base = h_default
      base.a1.a2.a3 = :foo
      expect(base.a1.a2.a3).to eq(:foo)
    end

    it 'can set all type of keys' do
      h = {}.to_lux_hash
      h[:foo1]  = :foo1
      h['foo2'] = :foo2
      h.foo3    = :foo3

      expect(h[:foo1]).to eq(:foo1)
      expect(h[:foo2]).to eq(:foo2)
      expect(h[:foo3]).to eq(:foo3)
    end

    it 'uses string key as a default' do
      h = {}.to_lux_hash
      h[:foo]  = { :bar => :symbol, 'bar' => 'string' }
      expect(h.foo.bar).to eq('string')
      expect(h[:foo]['bar']).to eq('string')
    end

    it 'allows weird key' do
      name  = 'a?#b'
      value = :value

      h = {}.to_lux_hash
      h[name] = value

      expect(h[name]).to eq(value)
    end

    it 'it allows special key name' do
      h = { foo: :bar, keys: :baz, size: 453, length: 'foo' }.to_lux_hash

      expect(h.keys).to eq(['foo', 'keys', 'size', 'length'])
      expect(h[:keys]).to eq(:baz)
      expect(h['keys']).to eq(:baz)

      expect(h.size).to eq(453)
      expect(h[:size]).to eq(453)

      expect(h.length).to eq('foo')
      expect(h['length']).to eq('foo')

      expect(h.keys.length).to eq(4)
    end

    it 'can add proc to hash' do
      h = {}.to_lux_hash
      h.proc_test do |num|
        num * 123
      end

      expect(h.proc_test.call(2)).to eq(246)
    end

    it 'responds to each' do
      data = []

      for k, v in h_default
        data.push k
      end

      expect(data).to eq(%w(a1 b1))
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
        expect(v.b.c).to eq(1)
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
        expect(el.foo).to eq(123)
      end
    end

    it 'deletes a key' do
      h = h_default

      h[Hash] = 123

      expect(h[:a1][:a2].delete(:a3)).to eq(:a3_foo)
      expect(h[:a1][:a2].delete(:a3)).to eq(nil)
      expect(h[:a1][:a2][:a3]).to eq(nil)
      expect(h.delete(Hash)).to eq(123)
      expect(h[Hash]).to eq(nil)
    end

    it 'can delete keys' do
      h = { :foo => :bar, bar: :baz }.to_lux_hash
      expect(h[:foo]).to eq(:bar)
      h.delete(:foo)
      expect(h[:foo]).to eq(nil)

      expect(h[:bar]).to eq(:baz)
      h.delete('bar')
      expect(h[:bar]).to eq(nil)
      expect(h['bar']).to eq(nil)
    end

    it 'can access complex keys' do
      h = { 123 => :foo, String => :bar }.to_lux_hash

      expect(h[123]).to eq(:foo)
      expect(h[String]).to eq(:bar)
    end

    it 'can add keys' do
      h = { :foo => :bar, String => :bar }.to_lux_hash
      h[:bar] = {}
      h[:bar][:baz] = 123

      expect(h.bar.baz).to eq 123
      expect(h[:bar].baz).to eq 123
      expect(h.bar[:baz]).to eq 123
    end

    it 'can merge' do
      h  = { foo: :bar }.to_lux_hash
      nh = h.merge(foo: { jaz: :baz})

      expect(h.foo).to eq(:bar)
      expect(nh.foo.jaz).to eq(:baz)

      h.merge!(foo: { jaz: :baz})

      expect(h.foo.jaz).to eq(:baz)
    end

    it 'deletes key on method set' do
      h = {}.to_lux_hash
      h[:foo] = 123
      h.foo = 456
      expect(h.foo).to eq(456)
      expect(h[:foo]).to eq(456)
      expect(h['foo']).to eq(456)
    end

    it 'converts to string unless key is symbol' do
      h = {}.to_lux_hash
      h[123] = 456
      expect(h['123']).to eq(456)
    end

    it 'returns nested hash with Lux::Hash::Methods' do
      h1 = {
        foo: {
          bar: :baz
        }
      }.to_lux_hash

      h2 = h1[:foo]
      expect(h2.is_a?(Lux::Hash::Methods)).to eq(true)
    end

    it 'can push to array' do
      h = {foo: []}.to_lux_hash
      h[:foo].push 1
      h.foo.push 2
      expect(h.foo).to eq([1, 2])
    end
  end
end
