require 'test_helper'

class LuxHashFoo
  BAR = Lux::Hash(self, method: :bar) do |opt|
    opt.BAZ b: 'Baz'
  end

  Lux::Hash(self, method: :baz) do |opt|
    opt.VAL b: 'Value'
  end

  OPTS = Lux::Hash() do |opt|
    opt.set 'OPTA', :a, 'A name'
    opt.OPTB b: 'B name'
    opt.ACTIVE 1 => 'Active foo'
  end

  UNFOROZEN = Lux::Hash(freeze: false) do |opt|
    opt.ONE 1 => 'one'
  end

  # creates STATUS_INACTIVE = 0, STATUS_ACTIVE = 1, STATUS_DEAD = 2
  STATUS = Lux::Hash(self, constants: :status) do |opt|
    opt.INACTIVE 0 => 'Inactive object'
    opt.ACTIVE   1 => 'Active object'
    opt.DEAD     2 => 'Dead object'
  end
end

describe 'named options' do
  describe 'defines class method' do
    it 'creates class constant' do
      _(LuxHashFoo::BAR.BAZ).must_equal :b
    end

    it 'creates class method to access constant' do
      _(LuxHashFoo.bar.BAZ).must_equal :b
    end

    it 'is accesible via native constant' do
      _(LuxHashFoo::OPTS[1]).must_equal 'Active foo'
    end

    it 'is accesible via named option' do
      _(LuxHashFoo::OPTS.ACTIVE).must_equal 1
    end

    it 'if instructed does not create constant' do
      _{ LuxHashFoo::BAZ }.must_raise NameError
    end
  end

  describe 'does not pollute' do
    it 'creates via set' do
      _(LuxHashFoo::OPTS.OPTA).must_equal :a
    end

    it 'creates via method missing' do
      _(LuxHashFoo::OPTS.OPTB).must_equal :b
    end

    it 'gets name via code' do
      _(LuxHashFoo::OPTS[:b]).must_equal 'B name'
      _(LuxHashFoo::OPTS['b']).must_equal 'B name'
    end

    it 'ensures hash is frozen' do
      _{ LuxHashFoo::OPTS.ACTIVE = 2 }.must_raise FrozenError
    end

    it 'does not freeze if freeze false option given' do
      LuxHashFoo::UNFOROZEN.ONE = 2
      _(LuxHashFoo::UNFOROZEN.ONE).must_equal 2
    end

    it 'creates constants' do
      _(LuxHashFoo::STATUS[1]).must_equal 'Active object'
      _(LuxHashFoo::STATUS.ACTIVE).must_equal 1
      _(LuxHashFoo::STATUS_INACTIVE).must_equal 0
      _(LuxHashFoo::STATUS_ACTIVE).must_equal 1
      _(LuxHashFoo::STATUS_DEAD).must_equal 2
    end
  end
end
