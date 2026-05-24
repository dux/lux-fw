require 'test_helper'
require_relative '../loader'
require_relative '../api/kitchen_sink_api'

# Canonical reference test: exercises every DSL feature in one file.
# See spec/api/kitchen_sink_api.rb for the fixture.

describe 'KitchenSinkApi - DSL feature coverage' do
  # mount_on writes to a Lux::Api::OPTS global. Other api_tests/* specs
  # (notably sys_spec) also write to it, so we re-assert ours before any
  # test that reads it. Robust against load order.
  before { KitchenSinkApi.mount_on '/kapi' }

  describe 'class-level metadata' do
    it 'is registered in documented[]' do
      _(Lux::Api.documented).must_include KitchenSinkApi
    end

    it 'records class_desc, class_detail, icon' do
      opts = KitchenSinkApi.opts[:opts]
      _(opts[:desc]).must_equal 'Kitchen sink reference API'
      _(opts[:detail]).must_equal 'Exercises every Lux::Api DSL feature in one class.'
      _(opts[:icon]).must_include '<path'
    end

    it 'inherits mount_on from base' do
      _(Lux::Api::OPTS[:api][:mount_on]).must_equal '/kapi'
    end
  end

  describe 'collection actions' do
    it 'def list returns data and fires root before/after' do
      response = KitchenSinkApi.render :list
      _(response[:success]).must_equal true
      _(response[:data]).must_equal [{ id: 1 }, { id: 2 }]
      _(response[:meta][:tag]).must_equal 'kapi'
    end

    it 'def stash with params + allow :put' do
      opts = KitchenSinkApi.opts[:collection][:stash]
      _(opts[:allow]).must_equal ['PUT']
      _(opts[:desc]).must_equal 'Stash item via PUT'
      _(opts[:params][:name][:required]).must_equal true

      response = KitchenSinkApi.render :stash, params: { name: 'foo', nick: 'Some Label!' }
      _(response[:success]).must_equal true
      # :label Typero type normalizes to slug form
      _(response[:data][:nick]).must_be_kind_of String
    end

    it 'rejects stash without required name' do
      response = KitchenSinkApi.render :stash, params: { nick: 'x' }
      _(response[:success]).must_equal false
      assert response[:error][:details][:name]
    end

    it 'define :admin_action runs admin_only annotation' do
      response = KitchenSinkApi.render :admin_action
      _(response[:data]).must_equal({ admin: true })
    end

    it 'RESTful define get: :rest_get stores allow GET' do
      opts = KitchenSinkApi.opts[:collection][:rest_get]
      _(opts[:allow]).must_equal ['GET']
    end

    it 'RESTful define [:get, :put] => :rest_multi stores both' do
      opts = KitchenSinkApi.opts[:collection][:rest_multi]
      _(opts[:allow]).must_equal ['GET', 'PUT']
    end

    it 'unsafe sets opts[:unsafe]' do
      opts = KitchenSinkApi.opts[:collection][:public_action]
      _(opts[:unsafe]).must_equal true

      response = KitchenSinkApi.render :public_action
      _(response[:data]).must_equal true
    end
  end

  describe 'private helpers are hidden' do
    it 'current_user? (private root helper) is not an endpoint' do
      refute_includes (KitchenSinkApi.opts[:collection] || {}).keys, :current_user?

      response = KitchenSinkApi.render :current_user?
      _(response[:success]).must_equal false
    end

    it 'secret? (private predicate) is not an endpoint' do
      response = KitchenSinkApi.render :secret?
      _(response[:success]).must_equal false
    end

    it 'ref_helper (private inside ref do) is not an endpoint' do
      response = KitchenSinkApi.render :ref_helper, id: 1
      _(response[:success]).must_equal false
    end

    it 'private helpers ARE still callable from API methods' do
      # expose_user calls current_user? internally
      response = KitchenSinkApi.render :expose_user, bearer: 'tok'
      _(response[:success]).must_equal true
      _(response[:data][1]).must_equal 'tok'
      _(response[:data][2]).must_equal true
    end
  end

  describe 'ref scope' do
    it 'show sees @ref and ref-scoped before' do
      response = KitchenSinkApi.render :show, id: 'abc'
      _(response[:success]).must_equal true
      _(response[:data][:ref]).must_equal 'abc'
      _(response[:data][:root_before]).must_equal 1
      _(response[:data][:ref_before]).must_equal 1
    end

    it 'detail_action uses params inside ref do' do
      response = KitchenSinkApi.render :detail_action, id: 5, params: { verbose: 'true' }
      _(response[:data]).must_equal({ ref: 5, format: :long })
    end

    it 'ref methods are renamed to *_ref' do
      _(KitchenSinkApi.instance_methods).must_include :show_ref
      _(KitchenSinkApi.instance_methods).must_include :detail_action_ref
      refute_includes KitchenSinkApi.instance_methods, :show
      refute_includes KitchenSinkApi.instance_methods, :detail_action
    end
  end

  describe 'module include and plugin' do
    it 'KitchenSinkPing#ping is a collection action' do
      response = KitchenSinkApi.render :ping
      _(response[:data]).must_equal 'pong'
    end

    it 'plugin :kitchen_sink_plugin adds plugin_provided action' do
      response = KitchenSinkApi.render :plugin_provided
      _(response[:data]).must_equal 'from_plugin'
    end
  end

  describe 'rescue_from' do
    it 'named symbol error resolves message' do
      response = KitchenSinkApi.render :trigger_named_rescue, id: 1
      _(response[:success]).must_equal false
      _(response[:error][:messages]).must_include 'Forbidden'
    end

    it 'class-based rescue_from runs the block' do
      response = KitchenSinkApi.render :trigger_class_rescue, id: 1
      _(response[:success]).must_equal false
      _(response[:error][:messages]).must_include 'bad-arg'
    end
  end

  describe 'instance var exposure' do
    it 'expose_user receives @ref/@bearer_token' do
      response = KitchenSinkApi.render :expose_user, bearer: 'tok-1'
      _(response[:data][0]).must_be_nil  # collection - no @ref
      _(response[:data][1]).must_equal 'tok-1'
    end
  end
end

describe 'KitchenSinkChildApi - super / super!' do
  it 'collection action overrides parent with plain super' do
    response = KitchenSinkChildApi.render :list
    _(response[:data]).must_equal [{ id: 1 }, { id: 2 }, { id: 3 }]
  end

  it 'ref action overrides parent with super!' do
    response = KitchenSinkChildApi.render :show, id: 'k'
    _(response[:data][:ref]).must_equal 'k'
    _(response[:data][:extended]).must_equal true
  end
end
