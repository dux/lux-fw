require_relative '../loader'
require_relative '../api/kitchen_sink_api'

# Canonical reference test: exercises every DSL feature in one file.
# See spec/api/kitchen_sink_api.rb for the fixture.

describe 'KitchenSinkApi - DSL feature coverage' do
  context 'class-level metadata' do
    it 'is registered in documented[]' do
      expect(Lux::Api.documented).to include(KitchenSinkApi)
    end

    it 'records class_desc, class_detail, icon' do
      opts = KitchenSinkApi.opts[:opts]
      expect(opts[:desc]).to eq('Kitchen sink reference API')
      expect(opts[:detail]).to eq('Exercises every Lux::Api DSL feature in one class.')
      expect(opts[:icon]).to include('<path')
    end

    it 'inherits mount_on from base' do
      expect(Lux::Api::OPTS[:api][:mount_on]).to eq('/kapi')
    end
  end

  context 'collection actions' do
    it 'def list returns data and fires root before/after' do
      response = KitchenSinkApi.render :list
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq([{ id: 1 }, { id: 2 }])
      expect(response[:meta][:tag]).to eq('kapi')
    end

    it 'def stash with params + allow :put' do
      opts = KitchenSinkApi.opts[:collection][:stash]
      expect(opts[:allow]).to eq(['PUT'])
      expect(opts[:desc]).to eq('Stash item via PUT')
      expect(opts[:params][:name][:required]).to eq(true)

      response = KitchenSinkApi.render :stash, params: { name: 'foo', nick: 'Some Label!' }
      expect(response[:success]).to eq(true)
      # :label Typero type normalizes to slug form
      expect(response[:data][:nick]).to be_a(String)
    end

    it 'rejects stash without required name' do
      response = KitchenSinkApi.render :stash, params: { nick: 'x' }
      expect(response[:success]).to eq(false)
      expect(response[:error][:details][:name]).to be_truthy
    end

    it 'define :admin_action runs admin_only annotation' do
      response = KitchenSinkApi.render :admin_action
      expect(response[:data]).to eq({ admin: true })
    end

    it 'RESTful define get: :rest_get stores allow GET' do
      opts = KitchenSinkApi.opts[:collection][:rest_get]
      expect(opts[:allow]).to eq(['GET'])
    end

    it 'RESTful define [:get, :put] => :rest_multi stores both' do
      opts = KitchenSinkApi.opts[:collection][:rest_multi]
      expect(opts[:allow]).to eq(['GET', 'PUT'])
    end

    it 'unsafe sets opts[:unsafe]' do
      opts = KitchenSinkApi.opts[:collection][:public_action]
      expect(opts[:unsafe]).to eq(true)

      response = KitchenSinkApi.render :public_action
      expect(response[:data]).to eq(true)
    end
  end

  context 'private helpers are hidden' do
    it 'current_user? (private root helper) is not an endpoint' do
      expect(KitchenSinkApi.opts[:collection] || {}).not_to have_key(:current_user?)

      response = KitchenSinkApi.render :current_user?
      expect(response[:success]).to eq(false)
    end

    it 'secret? (private predicate) is not an endpoint' do
      response = KitchenSinkApi.render :secret?
      expect(response[:success]).to eq(false)
    end

    it 'ref_helper (private inside ref do) is not an endpoint' do
      response = KitchenSinkApi.render :ref_helper, id: 1
      expect(response[:success]).to eq(false)
    end

    it 'private helpers ARE still callable from API methods' do
      # expose_user calls current_user? internally
      response = KitchenSinkApi.render :expose_user, bearer: 'tok'
      expect(response[:success]).to eq(true)
      expect(response[:data][1]).to eq('tok')
      expect(response[:data][2]).to eq(true)
    end
  end

  context 'ref scope' do
    it 'show sees @ref and ref-scoped before' do
      response = KitchenSinkApi.render :show, id: 'abc'
      expect(response[:success]).to eq(true)
      expect(response[:data][:ref]).to eq('abc')
      expect(response[:data][:root_before]).to eq(1)
      expect(response[:data][:ref_before]).to eq(1)
    end

    it 'detail_action uses params inside ref do' do
      response = KitchenSinkApi.render :detail_action, id: 5, params: { verbose: 'true' }
      expect(response[:data]).to eq({ ref: 5, format: :long })
    end

    it 'ref methods are renamed to *_ref' do
      expect(KitchenSinkApi.instance_methods).to include(:show_ref, :detail_action_ref)
      expect(KitchenSinkApi.instance_methods).not_to include(:show, :detail_action)
    end
  end

  context 'module include and plugin' do
    it 'KitchenSinkPing#ping is a collection action' do
      response = KitchenSinkApi.render :ping
      expect(response[:data]).to eq('pong')
    end

    it 'plugin :kitchen_sink_plugin adds plugin_provided action' do
      response = KitchenSinkApi.render :plugin_provided
      expect(response[:data]).to eq('from_plugin')
    end
  end

  context 'rescue_from' do
    it 'named symbol error resolves message' do
      response = KitchenSinkApi.render :trigger_named_rescue, id: 1
      expect(response[:success]).to eq(false)
      expect(response[:error][:messages]).to include('Forbidden')
    end

    it 'class-based rescue_from runs the block' do
      response = KitchenSinkApi.render :trigger_class_rescue, id: 1
      expect(response[:success]).to eq(false)
      expect(response[:error][:messages]).to include('bad-arg')
    end
  end

  context 'instance var exposure' do
    it 'expose_user receives @ref/@bearer_token' do
      response = KitchenSinkApi.render :expose_user, bearer: 'tok-1'
      expect(response[:data][0]).to be_nil  # collection - no @ref
      expect(response[:data][1]).to eq('tok-1')
    end
  end
end

describe 'KitchenSinkChildApi - super / super!' do
  it 'collection action overrides parent with plain super' do
    response = KitchenSinkChildApi.render :list
    expect(response[:data]).to eq([{ id: 1 }, { id: 2 }, { id: 3 }])
  end

  it 'ref action overrides parent with super!' do
    response = KitchenSinkChildApi.render :show, id: 'k'
    expect(response[:data][:ref]).to eq('k')
    expect(response[:data][:extended]).to eq(true)
  end
end
