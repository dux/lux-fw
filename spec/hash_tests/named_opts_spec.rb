require 'spec_helper'

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
  context 'defines class method' do
    it 'creates class constant' do
      expect(LuxHashFoo::BAR.BAZ).to eq(:b)
    end

    it 'creates class method to access constant' do
      expect(LuxHashFoo.bar.BAZ).to eq(:b)
    end

    it 'is accesible via native constant' do
      expect(LuxHashFoo::OPTS[1]).to eq('Active foo')
    end

    it 'is accesible via named option' do
      expect(LuxHashFoo::OPTS.ACTIVE).to eq(1)
    end

    it 'if instructed does not create constant' do
      expect{ LuxHashFoo::BAZ }.to raise_error NameError
    end
  end

  context 'does not pollute' do
    it 'creates via set' do
      expect(LuxHashFoo::OPTS.OPTA).to eq(:a)
    end

    it 'creates via method missing' do
      expect(LuxHashFoo::OPTS.OPTB).to eq(:b)
    end

    it 'gets name via code' do
      expect(LuxHashFoo::OPTS[:b]).to eq('B name')
      expect(LuxHashFoo::OPTS['b']).to eq('B name')
    end

    it 'ensures hash is frozen' do
      expect{LuxHashFoo::OPTS.ACTIVE = 2}.to raise_error FrozenError
    end

    it 'does not freeze if freeze false option given' do
      expect{LuxHashFoo::UNFOROZEN.ONE = 2}.not_to raise_error
    end

    it 'creates constants' do
      expect(LuxHashFoo::STATUS[1]).to eq('Active object')
      expect(LuxHashFoo::STATUS.ACTIVE).to eq(1)
      expect(LuxHashFoo::STATUS_INACTIVE).to eq(0)
      expect(LuxHashFoo::STATUS_ACTIVE).to eq(1)
      expect(LuxHashFoo::STATUS_DEAD).to eq(2)
    end
  end
end
