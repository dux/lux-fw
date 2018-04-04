require 'spec_helper'

class Parent
  ClassAttributes.define self, :layout, :default
  ClassAttributes.define self, :layout_over, :default
  ClassAttributes.define self, :layout_nil
  ClassAttributes.define self, :layout_defined
end

class Child < Parent
  layout_defined :test
  layout_over :test
end

class Pet < Child
  layout_defined :test_pet
end

describe ClassAttributes do
  it 'speed should get good values' do
    expect(Pet.layout_defined).to eq(:test_pet)
    expect(Child.layout).to eq(:default)
    expect(Child.layout_nil).to eq(nil)
    expect(Child.layout_defined).to eq(:test)
    expect(Child.layout_over).to eq(:test)
  end
end
