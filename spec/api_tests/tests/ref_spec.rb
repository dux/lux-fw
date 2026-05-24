require 'test_helper'
require_relative '../loader'

# Tests the new lux-fw-style ref DSL: methods defined inside `ref do` are
# renamed to *_ref after the block, private helpers are hidden from the API,
# and @ref / @bearer_token are exposed to action bodies and callbacks.

class RefSpecBaseApi < Lux::Api
  def_registration_strict false

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
    _(RefSpecBaseApi.instance_method(:member_action_ref)).must_be_kind_of UnboundMethod
    _(RefSpecBaseApi.private_instance_methods(false)).must_include :secret_helper_ref
  end

  it 'registers ref methods under :member' do
    _(RefSpecBaseApi.opts[:member].key?(:member_action)).must_equal true
    _(RefSpecBaseApi.opts[:member].key?(:defined_in_ref)).must_equal true
  end

  it 'registers root public methods under :collection' do
    _(RefSpecBaseApi.opts[:collection].key?(:root_collection_action)).must_equal true
    _(RefSpecBaseApi.opts[:collection].key?(:see_ref_in_collection)).must_equal true
  end

  it 'does NOT register private helpers as endpoints (root)' do
    _((RefSpecBaseApi.opts[:collection] || {}).key?(:root_helper)).must_equal false
    response = RefSpecBaseApi.render :root_helper
    _(response[:success]).must_equal false
    _(response[:error][:messages].first).must_include 'Api method'
  end

  it 'does NOT register private helpers as endpoints (inside ref do)' do
    _((RefSpecBaseApi.opts[:member] || {}).key?(:secret_helper)).must_equal false
    # both the un-suffixed name AND _ref name should be rejected
    _(RefSpecBaseApi.render(:secret_helper, id: 1)[:success]).must_equal false
  end

  it 'sets @ref to the resource id for member actions' do
    response = RefSpecBaseApi.render :member_action, id: 'abc123'
    _(response[:success]).must_equal true
    _(response[:data].first).must_equal 'abc123'
  end

  it 'leaves @ref nil for collection actions' do
    response = RefSpecBaseApi.render :see_ref_in_collection
    _(response[:success]).must_equal true
    _(response[:data]).must_be_nil
  end

  it 'exposes @bearer_token before any callback' do
    response = RefSpecBaseApi.render :see_bearer_at_root, bearer: 'tok-xyz'
    _(response[:data]).must_equal 'tok-xyz'
  end

  it 'fires root before for both collection and ref' do
    response = RefSpecBaseApi.render :root_collection_action
    _(response[:data]).must_equal 1

    response = RefSpecBaseApi.render :member_action, id: 1
    # third element is @root_callback_seen, set by root before
    _(response[:data][2]).must_equal 1
  end

  it 'fires ref-scoped before only for ref actions' do
    response = RefSpecBaseApi.render :member_action, id: 1
    _(response[:data][3]).must_equal 1

    response = RefSpecBaseApi.render :root_collection_action
    _(response[:data]).must_equal 1
    # @ref_callback_seen would be nil for collection action
  end

  it 'define :foo inside ref do becomes :foo_ref' do
    _(RefSpecBaseApi.instance_method(:defined_in_ref_ref)).must_be_kind_of UnboundMethod

    response = RefSpecBaseApi.render :defined_in_ref, id: 42
    _(response[:data]).must_equal 'defined_ref_42'
  end
end

# super / super! across inheritance lines

class RefSpecParentApi < Lux::Api
  def_registration_strict false

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
    _(RefSpecChildApi.render(:parent_collection)[:data]).must_equal 'parent-c-overridden'
  end

  it 'super! works inside ref methods (no-arg)' do
    _(RefSpecChildApi.render(:parent_member, id: 1)[:data]).must_equal 'parent-m-overridden'
  end

  it 'super! with explicit name resolves member methods on superclass' do
    _(RefSpecChildApi.render(:with_explicit_super_bang, id: 1)[:data]).must_equal 'parent-m!shim'
  end
end
