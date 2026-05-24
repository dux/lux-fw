require 'test_helper'

class FooCustomExporter < Lux::JsonExporter
  define :export_2 do
    prop :num, model.sum * 2
  end

  define :export_4 do
    prop :num, model.sum * 4
  end
end

class BarExporter < Lux::JsonExporter
  define do
    prop :sum
  end
end

###

class Dog
  def kind
    'dog'
  end
end

class PetExporter < Lux::JsonExporter
  after do
    json[:foo] = :bar
  end
end

class DogPetExporter < PetExporter
  define do
    property :kind
    property :klass, self.class
  end
end

###

describe FooCustomExporter do
  def model
    @model ||= Struct.new(:sum).new(2)
  end

  it 'expects 2' do
    export = FooCustomExporter.export(model, exporter: :export_2)
    _(export[:num]).must_equal 4
  end

  it 'expects 4' do
    export = FooCustomExporter.export(model, exporter: 'Export4')
    _(export[:num]).must_equal 8
  end

  it 'expects 2' do
    export = BarExporter.export(model)
    _(export[:sum]).must_equal 2
  end

  it 'expects to find a pet class' do
    exported1 = DogPetExporter.export(Dog.new)
    _(exported1).must_equal({ kind: 'dog', foo: :bar, klass: DogPetExporter })

    exported2 = PetExporter.export(Dog.new)
    _(exported2).must_equal({ kind: 'dog', foo: :bar, klass: PetExporter })
  end
end
