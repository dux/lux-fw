require_relative '../loader'

# Tests the new lux-fw-style ref DSL: methods defined inside `ref do` are
# renamed to *_ref after the block, private helpers are hidden from the API,
# and @ref / @bearer_token are exposed to action bodies and callbacks.

class RefSpecBaseApi < Lux::Api
  before do
    @root_callback_seen = (@root_callback_seen || 0) + 1
  end

  def root_collection_action
    @root_callback_seen
  end

  def see_ref_in_collection
    @ref
  end

  ref do
    before do
      @ref_callback_seen = (@ref_callback_seen || 0) + 1
    end

    def member_action
      [@ref, @bearer_token, @root_callback_seen, @ref_callback_seen]
    end

    define :defined_in_ref do
      proc { "defined_ref_#{@ref}" }
    end

    private

    def secret_helper
      'no_one_should_see_this'
    end
  end

  def see_bearer_at_root
    @bearer_token
  end

  private

  def root_helper
    'also_secret'
  end
end

describe 'ref DSL' do
  it 'renames methods inside ref do to *_ref' do
    expect(RefSpecBaseApi.instance_method(:member_action_ref)).to be_a(UnboundMethod)
    expect(RefSpecBaseApi.private_instance_methods(false)).to include(:secret_helper_ref)
  end

  it 'registers ref methods under :member' do
    expect(RefSpecBaseApi.opts[:member]).to have_key(:member_action)
    expect(RefSpecBaseApi.opts[:member]).to have_key(:defined_in_ref)
  end

  it 'registers root public methods under :collection' do
    expect(RefSpecBaseApi.opts[:collection]).to have_key(:root_collection_action)
    expect(RefSpecBaseApi.opts[:collection]).to have_key(:see_ref_in_collection)
  end

  it 'does NOT register private helpers as endpoints (root)' do
    expect(RefSpecBaseApi.opts[:collection] || {}).not_to have_key(:root_helper)
    response = RefSpecBaseApi.render :root_helper
    expect(response[:success]).to eq(false)
    expect(response[:error][:messages].first).to include('Api method')
  end

  it 'does NOT register private helpers as endpoints (inside ref do)' do
    expect(RefSpecBaseApi.opts[:member] || {}).not_to have_key(:secret_helper)
    # both the un-suffixed name AND _ref name should be rejected
    expect(RefSpecBaseApi.render(:secret_helper, id: 1)[:success]).to eq(false)
  end

  it 'sets @ref to the resource id for member actions' do
    response = RefSpecBaseApi.render :member_action, id: 'abc123'
    expect(response[:success]).to eq(true)
    expect(response[:data].first).to eq('abc123')
  end

  it 'leaves @ref nil for collection actions' do
    response = RefSpecBaseApi.render :see_ref_in_collection
    expect(response[:success]).to eq(true)
    expect(response[:data]).to be_nil
  end

  it 'exposes @bearer_token before any callback' do
    response = RefSpecBaseApi.render :see_bearer_at_root, bearer: 'tok-xyz'
    expect(response[:data]).to eq('tok-xyz')
  end

  it 'fires root before for both collection and ref' do
    response = RefSpecBaseApi.render :root_collection_action
    expect(response[:data]).to eq(1)

    response = RefSpecBaseApi.render :member_action, id: 1
    # third element is @root_callback_seen, set by root before
    expect(response[:data][2]).to eq(1)
  end

  it 'fires ref-scoped before only for ref actions' do
    response = RefSpecBaseApi.render :member_action, id: 1
    expect(response[:data][3]).to eq(1)

    response = RefSpecBaseApi.render :root_collection_action
    expect(response[:data]).to eq(1)
    # @ref_callback_seen would be nil for collection action
  end

  it 'define :foo inside ref do becomes :foo_ref' do
    expect(RefSpecBaseApi.instance_method(:defined_in_ref_ref)).to be_a(UnboundMethod)

    response = RefSpecBaseApi.render :defined_in_ref, id: 42
    expect(response[:data]).to eq('defined_ref_42')
  end
end

# super / super! across inheritance lines

class RefSpecParentApi < Lux::Api
  def parent_collection
    'parent-c'
  end

  ref do
    def parent_member
      'parent-m'
    end
  end
end

class RefSpecChildApi < RefSpecParentApi
  def parent_collection
    super + '-overridden'
  end

  ref do
    # Inside ref do, methods are renamed via UnboundMethod#bind, so plain
    # Ruby `super` looks for the *original* (un-suffixed) name on the
    # superclass and fails. Use the `super!` shim instead, which derives
    # the correct *_ref name automatically.
    def parent_member
      super! + '-overridden'
    end

    def with_explicit_super_bang
      super!('parent_member') + '!shim'
    end
  end
end

describe 'super and super! across ref/collection' do
  it 'plain super works in collection methods' do
    expect(RefSpecChildApi.render(:parent_collection)[:data]).to eq('parent-c-overridden')
  end

  it 'super! works inside ref methods (no-arg)' do
    expect(RefSpecChildApi.render(:parent_member, id: 1)[:data]).to eq('parent-m-overridden')
  end

  it 'super! with explicit name resolves member methods on superclass' do
    expect(RefSpecChildApi.render(:with_explicit_super_bang, id: 1)[:data]).to eq('parent-m!shim')
  end
end
