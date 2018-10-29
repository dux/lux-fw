require 'spec_helper'

class Parent
  class_attribute :layout, :default
  class_attribute :layout_over, :default
  class_attribute :layout_nil
  class_attribute :layout_defined
end

class Child < Parent
  layout_defined :test
  layout_over :test
end

class Pet < Child
  layout_defined :test_pet
end

describe 'ClassAttributes' do
  it 'speed should get good values' do
    expect(Pet.layout_defined).to eq(:test_pet)
    expect(Child.layout_defined).to eq(:test)
    expect(Child.layout).to eq(:default)
    expect(Child.layout_nil).to eq(nil)
    expect(Child.layout_over).to eq(:test)
  end

  it 'should not get defeined twice' do
    Child.layout :foo

    expect(Child.layout).to eq(:foo)

    Parent.class_attribute :layout, self

    expect(Child.layout).to eq(:foo)
  end
end
