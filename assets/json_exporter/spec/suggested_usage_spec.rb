require 'spec_helper'

###

class Cat
  def kind
    'cat'
  end
end

class Cow
  def kind
    'cow'
  end
end

class Mouse
  def kind
    'mouse'
  end
end

###

class PetsExporter < Lux::JsonExporter
  after do
    json[:foo] = :bar
  end

  define Cat do
    prop :kind
    prop :num, 1
  end
end

class CowPetsExporter < PetsExporter
  define do
    property :kind
    prop :num, 2
  end
end

class StrangeExporter < PetsExporter
  after do
    json[:strange] = true
  end
end

class SuperStrangeExporter < StrangeExporter
end

###

describe Lux::JsonExporter do
  it 'expects that is export simple' do
    result = PetsExporter.export(Cat.new)
    expect(result).to eq({ kind: 'cat', num: 1, foo: :bar })
  end

  it 'expects to fail' do
    expect { PetsExporter.export(Mouse.new) }.to raise_error(StandardError)
  end

  it 'expects that is export simple' do
    result  = PetsExporter.export(Cow.new)
    expect(result).to eq({ kind: 'cow', num: 2, foo: :bar })
  end

  it 'expects nested exporter to work' do
    result  = SuperStrangeExporter.export(Cat.new)
    expect(result).to eq({ kind: 'cat', num: 1, strange: true, foo: :bar })
  end
end
