require 'test_helper'

# Test-specific config: no static files, no asset root, no CSRF, because this
# spec drives the full Lux.render request pipeline (other defaults come from
# Lux::Boot.apply_defaults on the first Lux.config read).
%i(serve_static_files asset_root csrf).each do |k|
  Lux.config[k] = false unless Lux.config.key?(k)
end

class ExplodingRouter < Lux::Router
  def boom
    raise 'BOOM!'
  end

  def boom_via_map
    raise 'BOOM2'
  end

  def denied
    raise Lux::Policy::Error, 'DENIED'
  end
end

class AfterMutateRouter < Lux::Router
  def show
    render text: 'hello'
  end
end

# a handler that knows the size without building the body, the way a proxied
# file HEAD does
class HeadLengthRouter < Lux::Router
  def show
    response.headers['content-length'] = '1024'
    response.body ''
  end
end

class AppRescueRenderRouter < Lux::Router
  def show
    render text: 'APP-CATCH(%d): %s' % [@status, @error.message]
  end
end

class RoutesTestRouter < Lux::Router
  def index
    render text: 'root'
  end

  # but the legacy test expected "tilda" from index; keep a dedicated route
  def tilda
    render text: 'tilda'
  end

  def user
    render text: 'user'
  end

  def foo
    render text: Lux.ctx.params[:foo]
  end

  def city
    render text: 'zagreb'
  end

  def nested
    respond_to(:js) do
      render json: { a: 1 }
    end

    render text: 'nested'
  end

  def multi_format
    respond_to(:csv) { render text: 'csv' }
    respond_to(:json) { render json: { f: 'json' } }
    render text: 'html' unless Lux.ctx.response.body?
  end

  def strict_format
    respond_to!(:json) { render json: { f: 'json' } }
    render text: 'html' unless Lux.ctx.response.body?
  end

  allow :post
  def posted
    render text: 'posted'
  end
end

class MountedRackApp
  def self.call(env)
    body = 'mounted:%s:%s' % [env['SCRIPT_NAME'], env['PATH_INFO']]
    [200, { 'content-type' => 'text/plain' }, [body]]
  end
end

# Rack app answering 204 with an empty body array - must still end routing
module NoContentRackApp
  def self.call env
    [204, {}, []]
  end
end

# Lux::Api subclass used to verify that map/call auto-detect API targets and
# pass the correct mount_at (consumed-prefix) via Rack SCRIPT_NAME so the
# API's auto_mount sees the right URL split.
class MountedTestApi < Lux::Api
  unsafe
  allow :get
  define :ping do
    proc { 'pong' }
  end
end

# echoes its params; default verb is POST
class MountedEchoApi < Lux::Api
  unsafe
  define :echo do
    proc { params.to_h }
  end
end

class BoardsRouter < Lux::Router
  def index;   render text: 'boards:index';   end
  def new;     render text: 'boards:new';     end
  def archive; render text: 'boards:archive'; end
  def show;    render text: 'boards:show';    end
  def edit;    render text: 'boards:edit';    end
end

class ProfileRouter < Lux::Router
  def index; render text: 'profile:index'; end
  def edit;  render text: 'profile:edit'; end
end

class AdminTestRouter < Lux::Router
  def index; render text: 'admin:index:';                end
  def edit;  render text: "admin:edit:#{nav.ref}";       end
  def users; render text: "admin:users:#{nav.ref}";      end
  def foo;   render text: "admin:foo:#{nav.ref}";        end
  def bar;   render text: "admin:bar:#{nav.ref}";        end
  def show;  render text: "admin:show:#{nav.ref}";       end
end

# mounted without matching: sees the whole cursor it was mounted at
class SpecPromoRouter < Lux::Router
  route { render text: "promo:#{Lux.ctx.route.path.join('/')}" }
end

class IvarProbeRouter < Lux::Router
  def show = render(text: "seen:#{@seen}")
end

class BeforeCountParentRouter < Lux::Router
  before { Lux.ctx.var[:parent_before] = Lux.ctx.var[:parent_before].to_i + 1 }
end

class BeforeCountRouter < BeforeCountParentRouter
  before { Lux.ctx.var[:child_before] = Lux.ctx.var[:child_before].to_i + 1 }

  route { map 'deep', 'before_count_deep#show' }
end

class BeforeCountDeepRouter < BeforeCountParentRouter
  def show
    render text: %i[root_before parent_before child_before].map { "#{_1}=#{Lux.ctx.var[_1].to_i}" }.join(' ')
  end
end

class RenderStopRouter < Lux::Router
  def show
    render text: 'once'
    raise 'code after render ran'
  end
end

class ChildRescueRouter < Lux::Router
  rescue_from { |err| render text: "child:#{err.message}" }

  def show = raise('oops')
end

class EmptyRouteRouter < Lux::Router
  route { @nothing = true }
end

class LayoutSwitchRouter < Lux::Router
  template_root './spec/fixtures/views'
  layout :boards

  before { layout :pages }

  route { auto }
end

###

Lux.router do
  after do
    if request.path == '/after-mutate'
      response.body { |b| b.gsub('hello', 'GREETINGS-FRIEND') }
    end
  end

  rescue_from do |err|
    map 'app_rescue_render#show'
  end

  before do
    # canonicalize ID-like segments to :ref before routing
    nav.map_path { |el| el =~ /\A\d+\z/ ? el : nil }
    Lux.ctx.var[:root_before] = Lux.ctx.var[:root_before].to_i + 1
  end

  def root_meth = render(text: 'root-meth')
  def edit_card = render(text: "edit-card:#{nav.ref}")
end

ROUTES_SPEC_ROUTE ||= proc do
  @seen = 'root-ivar'

  root 'routes_test#index'

  map 'boards', 'boards'
  map 'profile', 'profile'
  map 'admin_test', 'admin_test'

  map 'plain' do
    render text: 'plain'
  end

  map 'binary' do
    render text: "\x89PNG", content_type: :png
  end

  map 'city' do
    root 'routes_test#city'
    map 'user', 'routes_test#user'
  end

  post? { map 'post_scope', 'routes_test#posted' }

  subdomain 'sub' do
    map 'page', 'routes_test#user'
  end

  map %w[array1 array2], 'routes_test#index'

  # same source line, two calls - both must dispatch
  %w[looped1 looped2].each { |path| map path, 'routes_test#index' }

  map '/test1/test2/:foo', 'routes_test#foo'

  map 'zagreb', 'routes_test#city'

  map 'routes_test' do
    map 'foo-nested', 'routes_test#nested'
    map 'multi-format', 'routes_test#multi_format'
    map 'strict-format', 'routes_test#strict_format'
  end

  map 'exploding', 'exploding#boom'
  map 'exploding-via-map', 'exploding#boom_via_map'
  map 'exploding-denied', 'exploding#denied'
  map 'after-mutate', 'after_mutate#show'
  map 'head-length', 'head_length#show'

  # Rack-app dispatch: any class responding to .call(env) is routed via
  # `map` exactly like a router.
  map '/r1',          MountedRackApp     # absolute path
  map '/foo/bar/baz', MountedRackApp     # deep absolute path
  map 'r3',           MountedRackApp     # single segment
  map '/r204',        NoContentRackApp

  # Lux::Api dispatch: a Lux::Api subclass is mounted as a rack app with
  # mount_at derived from the consumed route prefix so the API auto_mount
  # splits the URL at the right place.
  map '/admin/api', MountedTestApi         # absolute deep path
  map 'api1',       MountedTestApi         # single segment
  map 'echo-api',   MountedEchoApi

  map 'promo-any' do
    map SpecPromoRouter
  end

  map 'root-meth', :root_meth
  map 'cards', :ref, 'edit', :edit_card
  map 'ivar-probe', 'ivar_probe#show'
  map 'before-count', BeforeCountRouter
  map 'render-stop', 'render_stop#show'
  map 'child-rescue', 'child_rescue#show'
  map 'empty-route', EmptyRouteRouter
  map 'layout-switch', LayoutSwitchRouter

  render text: 'not found', status: 404
end

###

describe 'Lux::Router' do
  before { Lux.router.route(&ROUTES_SPEC_ROUTE) }

  it 'should get right routes' do
    _(Lux.render.get('/').body).must_equal 'root'
    _(Lux.render.get('/plain').body).must_equal 'plain'
  end

  it 'registers every route declared from one line in a loop' do
    _(Lux.render.get('/looped1').body).must_equal 'root'
    _(Lux.render.get('/looped2').body).must_equal 'root'
  end

  it 'adds a charset to text content types only' do
    _(Lux.render.get('/plain').headers['content-type']).must_equal 'text/plain; charset=utf-8'
    _(Lux.render.get('/binary').headers['content-type']).must_equal 'image/png'
  end

  it 'rejects bad map shapes with the canonical form in the message' do
    app = Lux::Router.new('/')
    error = assert_raises(ArgumentError) { app.map(user: 'routes_test#user') }
    assert_includes error.message, "map 'users', UsersRouter"
    error = assert_raises(ArgumentError) { app.map('routes_test') }
    assert_includes error.message, 'map UsersRouter'
    error = assert_raises(ArgumentError) { app.map({ a: 1 }, 'routes_test#user') }
    assert_includes error.message, 'path segments'
  end

  it 'should get nested routes' do
    _(Lux.render.get('/test1/test2/bar').body).must_equal 'bar'
    _(Lux.render.get('/routes_test/foo-nested').body).must_equal 'nested'
  end

  it 'should get list routes' do
    _(Lux.render.get('/array1').body).must_equal 'root'
    _(Lux.render.get('/array2').body).must_equal 'root'
  end

  it 'should get namespace routes' do
    _(Lux.render.get('/zagreb').body).must_equal 'zagreb'
    _(Lux.render.get('/city').body).must_equal 'zagreb'
    _(Lux.render.get('/city/user').body).must_equal 'user'
  end

  it 'should get bad routes' do
    _(Lux.render.get('/not-found').status).must_equal 404
    _(Lux.render.get('/x@dux').status).must_equal 404
  end

  describe 'Rack-class dispatch via map' do
    it 'routes an absolute root prefix to RackClass.call(env)' do
      res = Lux.render.get('/r1/hello')
      _(res.status).must_equal 200
      # SCRIPT_NAME is empty - the Rack app sees the full path verbatim
      _(res.body).must_equal 'mounted::/r1/hello'
    end

    it 'routes a deep absolute prefix' do
      res = Lux.render.get('/foo/bar/baz/sub/page')
      _(res.status).must_equal 200
      _(res.body).must_equal 'mounted::/foo/bar/baz/sub/page'
    end

    it 'routes via a symbol shortcut on a single segment' do
      res = Lux.render.get('/r3')
      _(res.status).must_equal 200
      _(res.body).must_equal 'mounted::/r3'
    end

    it 'leaves unmatched requests alone' do
      _(Lux.render.get('/totally-different').status).must_equal 404
    end
  end

  describe 'rack app with empty body' do
    it 'ends routing on 204 instead of falling through to 404' do
      _(Lux.render.get('/r204').status).must_equal 204
    end
  end

  describe 'Lux::Api dispatch via map' do
    it 'mounts a Lux::Api subclass at a deep absolute path' do
      res = Lux.render.get('/admin/api/mounted_test/ping')
      _(res.status).must_equal 200
      _(res.json[:data]).must_equal 'pong'
    end

    it 'mounts a Lux::Api subclass at a single-segment symbol path' do
      res = Lux.render.get('/api1/mounted_test/ping')
      _(res.status).must_equal 200
      _(res.json[:data]).must_equal 'pong'
    end

    # Lux::Context reads the JSON body before the API runs; the API takes its
    # params from there, as sent (escaping happens on HTML output only)
    it 'passes JSON body and query params to the API' do
      res = Lux.render.post('/echo-api/mounted_echo/echo?q=1', body: '{"space_ref":"abc","name":"<b>"}', headers: { 'Content-Type' => 'application/json' })
      _(res.status).must_equal 200
      _(res.json[:data][:space_ref]).must_equal 'abc'
      _(res.json[:data][:q]).must_equal '1'
      _(res.json[:data][:name]).must_equal '<b>'
      _(Lux.ctx.params[:name]).must_equal '<b>'
    end
  end

  describe 'verb-scope and subdomain blocks' do
    it 'dispatches from inside a post? { } block' do
      _(Lux.render.post('/post_scope').body).must_equal 'posted'
    end

    it 'does not match the post? scope on GET' do
      _(Lux.render.get('/post_scope').status).must_equal 404
    end

    it 'dispatches from inside a subdomain block' do
      _(Lux.render.get('http://sub.example.com/page').body).must_equal 'user'
    end

    it 'leaves other subdomains alone' do
      _(Lux.render.get('http://other.example.com/page').status).must_equal 404
    end
  end

  it 'should render js route' do
    _(Lux.render.get('/routes_test/foo-nested.js').json[:a]).must_equal 1
  end

  it 'chains respond_to across formats' do
    _(Lux.render.get('/routes_test/multi-format.json').json[:f]).must_equal 'json'
    _(Lux.render.get('/routes_test/multi-format.csv').body).must_equal 'csv'
    _(Lux.render.get('/routes_test/multi-format').body).must_equal 'html'
  end

  it 'respond_to! 404s on another explicit format' do
    _(Lux.render.get('/routes_test/strict-format.json').json[:f]).must_equal 'json'
    _(Lux.render.get('/routes_test/strict-format').body).must_equal 'html'
    _(Lux.render.get('/routes_test/strict-format.csv').status).must_equal 404
  end

  it 'dispatches errors through Router rescue_from when defined (always wins)' do
    res = Lux.render.get('/exploding')
    _(res.status).must_equal 500
    _(res.body).must_equal 'APP-CATCH(500): BOOM!'
  end

  it 'rescue_from with `map` dispatches unconditionally' do
    res = Lux.render.get('/exploding-via-map')
    _(res.status).must_equal 500
    _(res.body).must_equal 'APP-CATCH(500): BOOM2'
  end

  it 'answers a policy denial with 403, not 500' do
    res = Lux.render.get('/exploding-denied')
    _(res.status).must_equal 403
    _(res.body).must_equal 'APP-CATCH(403): DENIED'
  end

  it 'fires Router :after BEFORE headers, so content-length matches the mutated body' do
    res = Lux.render.get('/after-mutate')
    _(res.body).must_equal 'GREETINGS-FRIEND'
    _(res.headers['content-length']).must_equal 'GREETINGS-FRIEND'.bytesize.to_s
  end

  it 'keeps a content-length a HEAD handler declared instead of building the body' do
    res = Lux.render.head('/head-length')
    _(res.headers['content-length']).must_equal '1024'
    _(res.body).must_equal ''
  end

  it 'ignores a declared content-length on GET, where the body is what ships' do
    res = Lux.render.get('/head-length')
    _(res.headers['content-length']).must_equal '0'
  end

  describe 'resourceful map (single segment routers)' do
    it 'maps /boards (empty remaining) to :index' do
      _(Lux.render.get('/boards').body).must_equal 'boards:index'
    end

    it 'maps /boards/new to :new' do
      _(Lux.render.get('/boards/new').body).must_equal 'boards:new'
    end

    it 'maps /boards/123 (:ref only) to :show' do
      _(Lux.render.get('/boards/123').body).must_equal 'boards:show'
    end

    it 'maps /boards/123/edit to :edit' do
      _(Lux.render.get('/boards/123/edit').body).must_equal 'boards:edit'
    end

    it 'maps /boards/archive (single action segment) to that action' do
      _(Lux.render.get('/boards/archive').body).must_equal 'boards:archive'
    end

    it 'maps /profile (no further segment) to :index' do
      _(Lux.render.get('/profile').body).must_equal 'profile:index'
    end

    it 'maps /profile/edit to :edit' do
      _(Lux.render.get('/profile/edit').body).must_equal 'profile:edit'
    end
  end

  describe 'resourceful map action resolution' do
    it '/admin_test -> :index' do
      _(Lux.render.get('/admin_test').body).must_equal 'admin:index:'
    end

    it '/admin_test/edit -> :edit' do
      _(Lux.render.get('/admin_test/edit').body).must_equal 'admin:edit:'
    end

    it '/admin_test/123 (only a :ref left) -> :show with nav.ref' do
      _(Lux.render.get('/admin_test/123').body).must_equal 'admin:show:123'
    end

    it '/admin_test/123/edit -> :edit with nav.ref' do
      _(Lux.render.get('/admin_test/123/edit').body).must_equal 'admin:edit:123'
    end

    it '/admin_test/users -> :users (sub-resource as action)' do
      _(Lux.render.get('/admin_test/users').body).must_equal 'admin:users:'
    end

    it '/admin_test/users/123 -> :users (last non-ref segment) with nav.ref' do
      _(Lux.render.get('/admin_test/users/123').body).must_equal 'admin:users:123'
    end

    it '/admin_test/users/123/edit -> :edit with nav.ref' do
      _(Lux.render.get('/admin_test/users/123/edit').body).must_equal 'admin:edit:123'
    end

    it '/admin_test/users/foo/bar -> :bar (last segment wins)' do
      _(Lux.render.get('/admin_test/users/foo/bar').body).must_equal 'admin:bar:'
    end

    it '/admin_test/users/123/foo/bar -> :bar with nav.ref' do
      _(Lux.render.get('/admin_test/users/123/foo/bar').body).must_equal 'admin:bar:123'
    end
  end

  describe 'map dispatch' do
    it 'mounts a router class without matching a segment' do
      _(Lux.render.get('/promo-any/some/page').body).must_equal 'promo:some/page'
    end

    it 'runs a method of the root router from a Symbol target' do
      _(Lux.render.get('/root-meth').body).must_equal 'root-meth'
    end

    it 'answers root only when the cursor is empty' do
      _(Lux.render.get('/').body).must_equal 'root'
      _(Lux.render.get('/routes_test').status).must_equal 404
    end

    it 'matches several segments before the target' do
      _(Lux.render.get('/cards/123/edit').body).must_equal 'edit-card:123'
      _(Lux.render.get('/cards/123').status).must_equal 404
    end

    it 'copies ivars set in the root route into a mounted router' do
      _(Lux.render.get('/ivar-probe').body).must_equal 'seen:root-ivar'
    end

    it 'runs each before hook once across nested mounts' do
      _(Lux.render.get('/before-count/deep').body).must_equal 'root_before=1 parent_before=1 child_before=1'
    end

    it 'ends the action at render' do
      res = Lux.render.get('/render-stop')
      _(res.status).must_equal 200
      _(res.body).must_equal 'once'
    end

    it 'lets the innermost rescue_from win over the root one' do
      _(Lux.render.get('/child-rescue').body).must_equal 'child:oops'
    end

    it 'answers 404 when a mounted router renders nothing' do
      _(Lux.render.get('/empty-route').status).must_equal 404
    end

    it 'switches layout, views dir included, from a before hook' do
      body = Lux.render.get('/layout-switch/index').body
      _(body).must_include 'layout:pages'
      _(body).must_include 'page:index'
    end
  end

  describe 'router class guards' do
    it 'refuses an action that shadows the routing DSL' do
      error = assert_raises(NameError) { Class.new(Lux::Router) { def map; end } }
      assert_includes error.message, 'shadows the Lux::Router DSL'
    end

    it 'accepts after on the root router only' do
      error = assert_raises(ArgumentError) { Class.new(Lux::Router) { after {} } }
      assert_includes error.message, 'root router'
      Lux.router { after {} }
    end
  end
end
