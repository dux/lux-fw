require 'test_helper'

# Default action: GET + HEAD + OPTIONS.
class GetDefaultRouter < Lux::Router
  def show
    render text: 'show:%s' % Lux.ctx.request.request_method
  end
end

# POST-only: allow replaces the default, doesn't add to it.
class AllowPostRouter < Lux::Router
  allow :post
  def create
    render text: 'create:%s' % Lux.ctx.request.request_method
  end
end

# POST + PATCH only.
class AllowMultiRouter < Lux::Router
  allow :post, :patch
  def update
    render text: 'update:%s' % Lux.ctx.request.request_method
  end
end

# Explicit GET + POST (the form to use when both verbs are wanted).
class AllowGetPostRouter < Lux::Router
  allow :get, :post
  def upsert
    render text: 'upsert:%s' % Lux.ctx.request.request_method
  end
end

# Explicit POST + OPTIONS.
class AllowPostOptionsRouter < Lux::Router
  allow :post, :options
  def preflight
    render text: 'preflight:%s' % Lux.ctx.request.request_method
  end
end

# Splat form with multiple verbs.
class AllowSplatRouter < Lux::Router
  allow :put, :delete
  def replace
    render text: 'replace:%s' % Lux.ctx.request.request_method
  end
end

# :any escape hatch.
class AllowAnyRouter < Lux::Router
  allow :any
  def webhook
    render text: 'webhook:%s' % Lux.ctx.request.request_method
  end
end

# :all - alias of :any.
class AllowAllRouter < Lux::Router
  allow :all
  def hook
    render text: 'hook:%s' % Lux.ctx.request.request_method
  end
end

# Two actions in the same class: allows must not leak between defs.
class AllowIsolationRouter < Lux::Router
  allow :post
  def create
    render text: 'create:%s' % Lux.ctx.request.request_method
  end

  def show
    render text: 'show:%s' % Lux.ctx.request.request_method
  end
end

# Ref-bearing action - `allow` applies the same way whether or not the URL
# carries a ref; the action reads nav.ref.
class AllowRefRouter < Lux::Router
  allow :delete
  def destroy
    render text: 'destroy:%s:%s' % [Lux.ctx.nav.ref, Lux.ctx.request.request_method]
  end
end

# GET-only action used as a rescue_from target.
class AllowErrorRouter < Lux::Router
  def error
    @status ||= 500
    render text: 'error:%s:%s' % [@status, Lux.ctx.request.request_method]
  end
end

###

describe 'Lux::Router allow / HTTP verb enforcement' do
  describe 'default GET' do
    it 'accepts GET' do
      Lux::Context.new('http://test/show')
      GetDefaultRouter.action(:show)
      _(Lux.ctx.response.body).must_equal 'show:GET'
    end

    it 'accepts HEAD (implicit alongside GET)' do
      Lux::Context.new('http://test/show', method: 'HEAD')
      GetDefaultRouter.action(:show)
      _(Lux.ctx.response.body).must_equal 'show:HEAD'
    end

    it 'accepts OPTIONS (implicit alongside GET)' do
      Lux::Context.new('http://test/show', method: 'OPTIONS')
      GetDefaultRouter.action(:show)
      _(Lux.ctx.response.body).must_equal 'show:OPTIONS'
    end

    it 'rejects POST with 405' do
      Lux::Context.new('http://test/show', method: 'POST')
      err = _{ GetDefaultRouter.action(:show) }.must_raise Lux::Error
      _(err.status).must_equal 405
    end

    it 'names the accepted verbs in the Allow header on 405' do
      Lux::Context.new('http://test/show', method: 'POST')
      _{ GetDefaultRouter.action(:show) }.must_raise Lux::Error
      _(Lux.ctx.response.headers['allow'].split(', ').sort).must_equal %w[GET HEAD OPTIONS]
    end

    it 'rejects PUT, PATCH, DELETE with 405' do
      %w(PUT PATCH DELETE).each do |verb|
        Lux::Context.new('http://test/show', method: verb)
        err = _{ GetDefaultRouter.action(:show) }.must_raise Lux::Error
        _(err.status).must_equal 405
      end
    end
  end

  describe 'allow :post (replaces default, not additive)' do
    it 'accepts POST' do
      Lux::Context.new('http://test/create', method: 'POST')
      AllowPostRouter.action(:create)
      _(Lux.ctx.response.body).must_equal 'create:POST'
    end

    it 'rejects GET with 405 (allow replaces default)' do
      Lux::Context.new('http://test/create')
      err = _{ AllowPostRouter.action(:create) }.must_raise Lux::Error
      _(err.status).must_equal 405
    end

    it 'rejects HEAD with 405 (no implicit HEAD without :get)' do
      Lux::Context.new('http://test/create', method: 'HEAD')
      err = _{ AllowPostRouter.action(:create) }.must_raise Lux::Error
      _(err.status).must_equal 405
    end

    it 'rejects OPTIONS with 405 (no implicit OPTIONS without :get)' do
      Lux::Context.new('http://test/create', method: 'OPTIONS')
      err = _{ AllowPostRouter.action(:create) }.must_raise Lux::Error
      _(err.status).must_equal 405
    end

    it 'rejects PATCH with 405' do
      Lux::Context.new('http://test/create', method: 'PATCH')
      err = _{ AllowPostRouter.action(:create) }.must_raise Lux::Error
      _(err.status).must_equal 405
    end
  end

  describe 'allow :post, :patch (POST + PATCH only)' do
    it 'accepts POST' do
      Lux::Context.new('http://test/update', method: 'POST')
      AllowMultiRouter.action(:update)
      _(Lux.ctx.response.body).must_equal 'update:POST'
    end

    it 'accepts PATCH' do
      Lux::Context.new('http://test/update', method: 'PATCH')
      AllowMultiRouter.action(:update)
      _(Lux.ctx.response.body).must_equal 'update:PATCH'
    end

    it 'rejects GET' do
      Lux::Context.new('http://test/update')
      err = _{ AllowMultiRouter.action(:update) }.must_raise Lux::Error
      _(err.status).must_equal 405
    end

    it 'rejects DELETE' do
      Lux::Context.new('http://test/update', method: 'DELETE')
      err = _{ AllowMultiRouter.action(:update) }.must_raise Lux::Error
      _(err.status).must_equal 405
    end
  end

  describe 'allow :get, :post (explicit dual-verb)' do
    it 'accepts GET' do
      Lux::Context.new('http://test/upsert')
      AllowGetPostRouter.action(:upsert)
      _(Lux.ctx.response.body).must_equal 'upsert:GET'
    end

    it 'accepts HEAD (implicit because :get is declared)' do
      Lux::Context.new('http://test/upsert', method: 'HEAD')
      AllowGetPostRouter.action(:upsert)
      _(Lux.ctx.response.body).must_equal 'upsert:HEAD'
    end

    it 'accepts OPTIONS (implicit because :get is declared)' do
      Lux::Context.new('http://test/upsert', method: 'OPTIONS')
      AllowGetPostRouter.action(:upsert)
      _(Lux.ctx.response.body).must_equal 'upsert:OPTIONS'
    end

    it 'accepts POST' do
      Lux::Context.new('http://test/upsert', method: 'POST')
      AllowGetPostRouter.action(:upsert)
      _(Lux.ctx.response.body).must_equal 'upsert:POST'
    end

    it 'rejects PATCH' do
      Lux::Context.new('http://test/upsert', method: 'PATCH')
      err = _{ AllowGetPostRouter.action(:upsert) }.must_raise Lux::Error
      _(err.status).must_equal 405
    end
  end

  describe 'splat form: allow :put, :delete' do
    it 'accepts PUT' do
      Lux::Context.new('http://test/replace', method: 'PUT')
      AllowSplatRouter.action(:replace)
      _(Lux.ctx.response.body).must_equal 'replace:PUT'
    end

    it 'accepts DELETE' do
      Lux::Context.new('http://test/replace', method: 'DELETE')
      AllowSplatRouter.action(:replace)
      _(Lux.ctx.response.body).must_equal 'replace:DELETE'
    end
  end

  describe 'explicit allow :options' do
    it 'accepts OPTIONS without GET when declared' do
      Lux::Context.new('http://test/preflight', method: 'OPTIONS')
      AllowPostOptionsRouter.action(:preflight)
      _(Lux.ctx.response.body).must_equal 'preflight:OPTIONS'
    end
  end

  describe 'allow :any' do
    it 'accepts every verb' do
      %w(GET POST PUT PATCH DELETE TRACE).each do |verb|
        Lux::Context.new('http://test/webhook', method: verb)
        AllowAnyRouter.action(:webhook)
        _(Lux.ctx.response.body).must_equal 'webhook:%s' % verb
      end
    end
  end

  describe 'allow :all (alias of :any)' do
    it 'accepts every verb' do
      %w(GET POST PUT DELETE).each do |verb|
        Lux::Context.new('http://test/hook', method: verb)
        AllowAllRouter.action(:hook)
        _(Lux.ctx.response.body).must_equal 'hook:%s' % verb
      end
    end
  end

  describe 'isolation between defs' do
    it 'applies allow :post only to the next def' do
      Lux::Context.new('http://test/create', method: 'POST')
      AllowIsolationRouter.action(:create)
      _(Lux.ctx.response.body).must_equal 'create:POST'
    end

    it 'leaves the following def at GET-default' do
      Lux::Context.new('http://test/show', method: 'POST')
      err = _{ AllowIsolationRouter.action(:show) }.must_raise Lux::Error
      _(err.status).must_equal 405
    end
  end

  describe 'ref-bearing action' do
    it 'enforces allow when the URL carries a ref' do
      Lux::Context.new('http://test/things/abc', method: 'DELETE')
      Lux.ctx.nav.map_path { |el| el == 'abc' ? 'abc' : nil }
      AllowRefRouter.action(:destroy)
      _(Lux.ctx.response.body).must_equal 'destroy:abc:DELETE'
    end

    it 'still rejects undeclared verbs' do
      Lux::Context.new('http://test/things/abc', method: 'POST')
      Lux.ctx.nav.map_path { |el| el == 'abc' ? 'abc' : nil }
      err = _{ AllowRefRouter.action(:destroy) }.must_raise Lux::Error
      _(err.status).must_equal 405
    end
  end

  describe 'error page dispatch' do
    it 'skips the verb check so POSTed errors render' do
      Lux::Context.new('http://test/anything', method: 'POST')
      Lux.ctx.var[:error_page] = true
      AllowErrorRouter.action(:error)
      _(Lux.ctx.response.body).must_match(/^error:/)
    end
  end

  describe 'invalid declarations' do
    it 'raises ArgumentError at class load for unknown verbs' do
      err = _{
        Class.new(Lux::Router) do
          allow :bogus
        end
      }.must_raise ArgumentError
      _(err.message).must_match(/not a recognised HTTP verb/)
    end
  end

  describe 'dev-mode 405 hint' do
    it 'includes the action name, attempted verb and allowed list' do
      prev = Lux.debug?
      Lux.debug = true
      begin
        Lux::Context.new('http://test/show', method: 'PUT')
        raised = nil
        begin
          GetDefaultRouter.action(:show)
        rescue Lux::Error => err
          raised = err
        end
        refute_nil raised
        _(raised.message).must_include 'GetDefaultRouter#show'
        _(raised.message).must_include 'PUT'
        _(raised.message).must_include 'GET, HEAD, OPTIONS'
        _(raised.message).must_include 'allow :put'
      ensure
        Lux.debug = prev
      end
    end
  end

  describe 'prod-mode 405 message' do
    it 'is terse (no action / verb leakage)' do
      Lux::Context.new('http://test/show', method: 'PUT')
      raised = nil
      begin
        GetDefaultRouter.action(:show)
      rescue Lux::Error => err
        raised = err
      end
      refute_nil raised
      _(raised.message).must_equal '405 Method Not Allowed'
    end
  end
end
