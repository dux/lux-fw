require 'spec_helper'

class A
  attr_accessor :text
  attr_accessor :num

  class_callback :before
  class_callback :multy

  def initialize
    @num  = 10
    @text = ''
  end
end

class B < A
  before do
    @text += 'a'
  end

  multy do |num|
    @num *= (num + 1)
  end
end

class C < B
  before do
    @text += 'b'
  end

  multy do |num|
    @num *= (num + 2)
  end
end

###

describe 'ClassAttributes' do

  it 'should validate filter execution' do
    o = C.new
    Object.class_callback :before, o
    Object.class_callback :multy, o, 2

    expect(o.text).to eq 'ab'
    expect(o.num).to eq 120
  end

end
