require 'test_helper'

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
    _(result).must_equal({ kind: 'cat', num: 1, foo: :bar })
  end

  it 'expects to fail' do
    _{ PetsExporter.export(Mouse.new) }.must_raise StandardError
  end

  it 'expects that is export simple for cow' do
    result  = PetsExporter.export(Cow.new)
    _(result).must_equal({ kind: 'cow', num: 2, foo: :bar })
  end

  it 'expects nested exporter to work' do
    result  = SuperStrangeExporter.export(Cat.new)
    _(result).must_equal({ kind: 'cat', num: 1, strange: true, foo: :bar })
  end
end
