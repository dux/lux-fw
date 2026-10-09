require 'test_helper'

require_relative '../load/lib/application_api'
require_relative '../load/lib/model_api'

class SpecWidget; end
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

  it 'refuses two APIs serving one model' do
    err = _{ ModelApi.client_index [SpecWidgetsApi, SpecWidgetAdminApi] }.must_raise ArgumentError
    _(err.message).must_match(/SpecWidgetAdminApi and SpecWidgetsApi both serve SpecWidget/)
  end
end
