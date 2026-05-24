require 'test_helper'

###

Company2 = Struct.new(:name, :address)

Lux.json_exporter Company2 do
  prop :name
  prop :address
end

###

describe Lux::JsonExporter do
  it 'expects basic export to work' do
    name    = 'ACME 1'
    address = 'Nowhere 123'

    company = Company2.new(name, address)
    result  = Lux::JsonExporter.export(company)

    _(result[:name]).must_equal name
    _(result[:address]).must_equal address
  end
end
