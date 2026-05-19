require 'spec_helper'

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
  let!(:model) { Struct.new(:sum).new(2) }

  it 'expects 2' do
    export = FooCustomExporter.export(model, exporter: :export_2)
    expect(export[:num]).to eq(4)
  end

  it 'expects 4' do
    export = FooCustomExporter.export(model, exporter: 'Export4')
    expect(export[:num]).to eq(8)
  end

  it 'expects 2' do
    export = BarExporter.export(model)
    expect(export[:sum]).to eq(2)
  end

  it 'expects to find a pet class' do
    exported1 = DogPetExporter.export(Dog.new)
    expect(exported1).to eq({ kind: 'dog', foo: :bar, klass: DogPetExporter })

    exported2 = PetExporter.export(Dog.new)
    expect(exported2).to eq({ kind: 'dog', foo: :bar, klass: PetExporter })
  end
end
