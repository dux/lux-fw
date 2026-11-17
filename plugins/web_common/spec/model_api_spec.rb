require 'test_helper'

require_relative '../load/lib/application_api'
require_relative '../load/lib/model_api'

class SpecWidget
  def self.api_schema = Lux.schema { name String }
end

class SpecWidgetsApi < ModelApi
  generate :create
  generate :update
end

describe 'ModelApi.generate' do
  it 'lists the writable fields as generated create/update params' do
    _(SpecWidgetsApi.get(:collection, :create, :params).keys.map(&:to_s)).must_equal %w[name]
    _(SpecWidgetsApi.api_schema_ref).must_equal 'spec_widget'
  end
end

class SpecGadget
  def self.api_schema
    Lux.schema do
      name  String
      color? String
    end
  end
end

class SpecGadgetsApi < ModelApi; end

describe 'ModelApi#object_params' do
  it 'keeps only api_schema fields, toggles included' do
    api = SpecGadgetsApi.allocate
    api.instance_variable_set :@object, SpecGadget.new
    sent = { 'name' => 'x', 'toggle__color' => 'red', 'is_admin' => true, 'ref' => 'abc', 'created_at' => 1 }
    api.define_singleton_method(:params) { sent.to_lux_hash }

    _(api.object_params.keys.map(&:to_s).sort).must_equal %w[name toggle__color]
  end
end
