require 'test_helper'

require_relative '../load/lib/application_api'
require_relative '../load/lib/model_api'

class SpecWidget
  def self.api_schema = Lux.schema { name String }
end
class SpecPerson; end

class SpecWidgetsApi < ModelApi
  generate :create
  generate :update

  undocumented
  define :internal do
    proc { true }
  end
end

# irregular plural - SpecPeople.singularize would not find SpecPerson
class SpecPeopleApi < ModelApi
  model_class SpecPerson

  define_ref :archive do
    proc { true }
  end
end

# no SpecOrphan model - abstract, never on the index
class SpecOrphansApi < ModelApi; end

class SpecWidgetAdminApi < ModelApi
  model_class SpecWidget
end

describe 'ModelApi.client_index' do
  before do
    @index = ModelApi.client_index [SpecWidgetsApi, SpecPeopleApi, SpecOrphansApi]
  end

  it 'keys model APIs by model name with their path and actions' do
    _(@index.keys).must_equal %w[spec_person spec_widget]
    _(@index['spec_widget'][:path]).must_equal '/api/spec_widgets'
    assert_includes @index['spec_widget'][:collection], 'create'
    assert_includes @index['spec_widget'][:member], 'update'
  end

  it 'uses the declared model_class for irregular plurals' do
    _(@index['spec_person'][:path]).must_equal '/api/spec_people'
    assert_includes @index['spec_person'][:member], 'archive'
  end

  it 'leaves undocumented actions off the index' do
    refute_includes @index['spec_widget'][:collection], 'internal'
  end

  it 'lists the writable fields as generated create/update params' do
    _(SpecWidgetsApi.get(:collection, :create, :params).keys.map(&:to_s)).must_equal %w[name]
    _(SpecWidgetsApi.api_schema_ref).must_equal 'spec_widget'
  end

  it 'refuses two APIs serving one model' do
    err = _{ ModelApi.client_index [SpecWidgetsApi, SpecWidgetAdminApi] }.must_raise ArgumentError
    _(err.message).must_match(/SpecWidgetAdminApi and SpecWidgetsApi both serve SpecWidget/)
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
