require 'spec_helper'

# Default action: GET + HEAD only.
class GetDefaultController < Lux::Controller
  def show
    render text: 'show:%s' % lux.request.request_method
  end
end

# POST-only: allow replaces the default, doesn't add to it.
class AllowPostController < Lux::Controller
  allow :post
  def create
    render text: 'create:%s' % lux.request.request_method
  end
end

# POST + PATCH only.
class AllowMultiController < Lux::Controller
  allow :post, :patch
  def update
    render text: 'update:%s' % lux.request.request_method
  end
end

# Explicit GET + POST (the form to use when both verbs are wanted).
class AllowGetPostController < Lux::Controller
  allow :get, :post
  def upsert
    render text: 'upsert:%s' % lux.request.request_method
  end
end

# Splat form with multiple verbs.
class AllowSplatController < Lux::Controller
  allow :put, :delete
  def replace
    render text: 'replace:%s' % lux.request.request_method
  end
end

# :any escape hatch.
class AllowAnyController < Lux::Controller
  allow :any
  def webhook
    render text: 'webhook:%s' % lux.request.request_method
  end
end

# :all - alias of :any.
class AllowAllController < Lux::Controller
  allow :all
  def hook
    render text: 'hook:%s' % lux.request.request_method
  end
end

# Two actions in the same class: allows must not leak between defs.
class AllowIsolationController < Lux::Controller
  allow :post
  def create
    render text: 'create:%s' % lux.request.request_method
  end

  def show
    render text: 'show:%s' % lux.request.request_method
  end
end

# `ref do` interaction - allow above a def inside ref do must survive the
# rename to *_ref dispatch.
class AllowRefController < Lux::Controller
  ref do
    allow :delete
    def destroy
      render text: 'destroy:%s:%s' % [lux.nav.ref, lux.request.request_method]
    end
  end
end

# Error action must be implicitly :any.
class AllowErrorController < Lux::Controller
  def error
    @status ||= 500
    render text: 'error:%s:%s' % [@status, lux.request.request_method]
  end
end

###

describe 'Lux::Controller allow / HTTP verb enforcement' do
  describe 'default GET-only' do
    it 'accepts GET' do
      Lux::Current.new('http://test/show')
      GetDefaultController.action(:show)
      expect(Lux.current.response.body).to eq('show:GET')
    end

    it 'accepts HEAD (implicit alongside GET)' do
      Lux::Current.new('http://test/show', method: 'HEAD')
      GetDefaultController.action(:show)
      expect(Lux.current.response.body).to eq('show:HEAD')
    end

    it 'rejects POST with 405' do
      Lux::Current.new('http://test/show', method: 'POST')
      expect { GetDefaultController.action(:show) }.to raise_error(Lux::Error)
      expect(Lux.current.response.status).to eq(405)
    end

    it 'rejects PUT, PATCH, DELETE with 405' do
      %w(PUT PATCH DELETE).each do |verb|
        Lux::Current.new('http://test/show', method: verb)
        expect { GetDefaultController.action(:show) }.to raise_error(Lux::Error)
        expect(Lux.current.response.status).to eq(405)
      end
    end
  end

  describe 'allow :post (replaces default, not additive)' do
    it 'accepts POST' do
      Lux::Current.new('http://test/create', method: 'POST')
      AllowPostController.action(:create)
      expect(Lux.current.response.body).to eq('create:POST')
    end

    it 'rejects GET with 405 (allow replaces default)' do
      Lux::Current.new('http://test/create')
      expect { AllowPostController.action(:create) }.to raise_error(Lux::Error)
      expect(Lux.current.response.status).to eq(405)
    end

    it 'rejects HEAD with 405 (no implicit HEAD without :get)' do
      Lux::Current.new('http://test/create', method: 'HEAD')
      expect { AllowPostController.action(:create) }.to raise_error(Lux::Error)
      expect(Lux.current.response.status).to eq(405)
    end

    it 'rejects PATCH with 405' do
      Lux::Current.new('http://test/create', method: 'PATCH')
      expect { AllowPostController.action(:create) }.to raise_error(Lux::Error)
      expect(Lux.current.response.status).to eq(405)
    end
  end

  describe 'allow :post, :patch (POST + PATCH only)' do
    it 'accepts POST' do
      Lux::Current.new('http://test/update', method: 'POST')
      AllowMultiController.action(:update)
      expect(Lux.current.response.body).to eq('update:POST')
    end

    it 'accepts PATCH' do
      Lux::Current.new('http://test/update', method: 'PATCH')
      AllowMultiController.action(:update)
      expect(Lux.current.response.body).to eq('update:PATCH')
    end

    it 'rejects GET' do
      Lux::Current.new('http://test/update')
      expect { AllowMultiController.action(:update) }.to raise_error(Lux::Error)
      expect(Lux.current.response.status).to eq(405)
    end

    it 'rejects DELETE' do
      Lux::Current.new('http://test/update', method: 'DELETE')
      expect { AllowMultiController.action(:update) }.to raise_error(Lux::Error)
      expect(Lux.current.response.status).to eq(405)
    end
  end

  describe 'allow :get, :post (explicit dual-verb)' do
    it 'accepts GET' do
      Lux::Current.new('http://test/upsert')
      AllowGetPostController.action(:upsert)
      expect(Lux.current.response.body).to eq('upsert:GET')
    end

    it 'accepts HEAD (implicit because :get is declared)' do
      Lux::Current.new('http://test/upsert', method: 'HEAD')
      AllowGetPostController.action(:upsert)
      expect(Lux.current.response.body).to eq('upsert:HEAD')
    end

    it 'accepts POST' do
      Lux::Current.new('http://test/upsert', method: 'POST')
      AllowGetPostController.action(:upsert)
      expect(Lux.current.response.body).to eq('upsert:POST')
    end

    it 'rejects PATCH' do
      Lux::Current.new('http://test/upsert', method: 'PATCH')
      expect { AllowGetPostController.action(:upsert) }.to raise_error(Lux::Error)
      expect(Lux.current.response.status).to eq(405)
    end
  end

  describe 'splat form: allow :put, :delete' do
    it 'accepts PUT' do
      Lux::Current.new('http://test/replace', method: 'PUT')
      AllowSplatController.action(:replace)
      expect(Lux.current.response.body).to eq('replace:PUT')
    end

    it 'accepts DELETE' do
      Lux::Current.new('http://test/replace', method: 'DELETE')
      AllowSplatController.action(:replace)
      expect(Lux.current.response.body).to eq('replace:DELETE')
    end
  end

  describe 'allow :any' do
    it 'accepts every verb' do
      %w(GET POST PUT PATCH DELETE TRACE).each do |verb|
        Lux::Current.new('http://test/webhook', method: verb)
        AllowAnyController.action(:webhook)
        expect(Lux.current.response.body).to eq('webhook:%s' % verb)
      end
    end
  end

  describe 'allow :all (alias of :any)' do
    it 'accepts every verb' do
      %w(GET POST PUT DELETE).each do |verb|
        Lux::Current.new('http://test/hook', method: verb)
        AllowAllController.action(:hook)
        expect(Lux.current.response.body).to eq('hook:%s' % verb)
      end
    end
  end

  describe 'isolation between defs' do
    it 'applies allow :post only to the next def' do
      Lux::Current.new('http://test/create', method: 'POST')
      AllowIsolationController.action(:create)
      expect(Lux.current.response.body).to eq('create:POST')
    end

    it 'leaves the following def at GET-default' do
      Lux::Current.new('http://test/show', method: 'POST')
      expect { AllowIsolationController.action(:show) }.to raise_error(Lux::Error)
      expect(Lux.current.response.status).to eq(405)
    end
  end

  describe 'ref do interaction' do
    it 'enforces allow on the renamed *_ref action' do
      Lux::Current.new('http://test/things/abc', method: 'DELETE')
      Lux.current.nav.path(:ref) { |el| el == 'abc' ? 'abc' : nil }
      AllowRefController.action(:destroy_ref)
      expect(Lux.current.response.body).to eq('destroy:abc:DELETE')
    end

    it 'still rejects undeclared verbs on *_ref' do
      Lux::Current.new('http://test/things/abc', method: 'POST')
      Lux.current.nav.path(:ref) { |el| el == 'abc' ? 'abc' : nil }
      expect { AllowRefController.action(:destroy_ref) }.to raise_error(Lux::Error)
      expect(Lux.current.response.status).to eq(405)
    end
  end

  describe ':error action' do
    it 'is implicitly :any so POSTed errors render' do
      Lux::Current.new('http://test/anything', method: 'POST')
      AllowErrorController.action(:error)
      expect(Lux.current.response.body).to match(/^error:/)
    end
  end

  describe 'invalid declarations' do
    it 'raises ArgumentError at class load for unknown verbs' do
      expect {
        Class.new(Lux::Controller) do
          allow :bogus
        end
      }.to raise_error(ArgumentError, /not a recognised HTTP verb/)
    end
  end

  describe 'dev-mode 405 hint' do
    around do |ex|
      prev = Lux.mode.errors?
      Lux.mode.errors = true
      ex.run
    ensure
      Lux.mode.errors = prev
    end

    it 'includes the action name, attempted verb and allowed list' do
      Lux::Current.new('http://test/show', method: 'PUT')
      raised = nil
      begin
        GetDefaultController.action(:show)
      rescue Lux::Error => err
        raised = err
      end
      expect(raised).not_to be_nil
      expect(raised.message).to include('GetDefaultController#show')
      expect(raised.message).to include('PUT')
      expect(raised.message).to include('GET, HEAD')
      expect(raised.message).to include('allow :put')
    end
  end

  describe 'prod-mode 405 message' do
    it 'is terse (no action / verb leakage)' do
      Lux::Current.new('http://test/show', method: 'PUT')
      raised = nil
      begin
        GetDefaultController.action(:show)
      rescue Lux::Error => err
        raised = err
      end
      expect(raised).not_to be_nil
      expect(raised.message).to eq('405 Method Not Allowed')
    end
  end
end
