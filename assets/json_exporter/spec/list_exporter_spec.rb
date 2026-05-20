require 'spec_helper'

###

class Company3
  def name
    'comp'
  end

  def users
    [User3.new(:foo), User3.new(:bar)]
  end
end

class User3
  attr_accessor :name

  def initialize name
    @name = name
  end
end

class Company3Exporter < Lux::JsonExporter
  after do
    prop :kind, model.class.to_s
  end

  define do
    prop :name

    export :users
  end

  define User3 do
    prop :name
  end
end

###

describe Lux::JsonExporter do
  it 'expects to export lists' do
    model  = Company3.new
    export = Company3Exporter.export(model)

    expect(export[:users]).to eq(
      [
        { name: :foo, kind: 'User3' },
        { name: :bar, kind: 'User3' }
      ]
    )
  end
end
