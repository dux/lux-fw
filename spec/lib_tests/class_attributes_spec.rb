require 'test_helper'

describe 'cattr' do
  it 'evaluates a lambda default once, in the class scope' do
    klass = Class.new do
      cattr :x, class: true, default: -> { 1 }
    end
    _(klass.cattr.x).must_equal 1
  end

  it 'returns nil from a block default instead of the raw Proc' do
    klass = Class.new do
      cattr(:layout, class: true) { nil }
    end
    _(klass.cattr.layout).must_be_nil
  end
end
