require 'test_helper'

class RescueFromBase
  extend Lux::RescueFrom
  rescue_from { :all }
  rescue_from ArgumentError do :argument end
  rescue_from :forbidden, 'Forbidden'
end

class RescueFromChild < RescueFromBase
  rescue_from ArgumentError do :child_argument end
end

describe Lux::RescueFrom do
  it 'matches the error class and its subclasses before :all' do
    _(RescueFromBase.rescue_handler_for(ArgumentError.new).call).must_equal :argument
    _(RescueFromBase.rescue_handler_for(KeyError.new).call).must_equal :all
  end

  it 'lets the nearest class win for the same key' do
    _(RescueFromChild.rescue_handler_for(ArgumentError.new).call).must_equal :child_argument
    _(RescueFromChild.rescue_handler_for(RuntimeError.new).call).must_equal :all
  end

  it 'looks up named errors by key' do
    _(RescueFromChild.rescue_handler_for(:forbidden)).must_equal 'Forbidden'
    _(RescueFromChild.rescue_handler_for(:missing)).must_be_nil
  end

  it 'is the macro on Application, Controller and Api' do
    [Lux::Application, Lux::Controller, Lux::Api].each do |klass|
      _(klass.singleton_class.include?(Lux::RescueFrom)).must_equal true
    end
  end
end
