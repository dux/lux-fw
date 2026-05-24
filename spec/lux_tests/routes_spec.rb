require 'test_helper'

# Config defaults that Lux.boot! would normally set, needed because this spec
# exercises Lux.render which walks the full request pipeline.
%i(serve_static_files use_autoroutes asset_root deploy_timestamp csrf).each do |k|
  Lux.config[k] = false unless Lux.config.key?(k)
end
Lux.config[:plugins] ||= []
Lux.config[:logger_path_mask]     = './log/%s.log' unless Lux.config.key?(:logger_path_mask)
Lux.config[:logger_files_to_keep] = 3              unless Lux.config.key?(:logger_files_to_keep)
Lux.config[:logger_file_max_size] = 10_240_000     unless Lux.config.key?(:logger_file_max_size)
Lux.config[:logger_formatter]     = nil            unless Lux.config.key?(:logger_formatter)

class ExplodingController < Lux::Controller
  def boom
    raise 'BOOM!'
  end

  def boom_via_call
    raise 'BOOM2'
  end
end

class AfterMutateController < Lux::Controller
  def show
    render text: 'hello'
  end
end

class AppRescueRenderController < Lux::Controller
  def show
    render text: 'APP-CATCH(%d): %s' % [@status, @error.message]
  end
end

class RoutesTestController < Lux::Controller
  def root
    render text: 'root'
  end

  # used by /~ regex map => RoutesTestController (resourceful, empty -> :root)
  # but the legacy test expected "tilda" from index; keep a dedicated route
  def tilda
    render text: 'tilda'
  end

  def user
    render text: 'user'
  end

  def foo
    render text: lux.params[:foo]
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
end

class MountedRackApp
  def self.call(env)
    body = 'mounted:%s:%s' % [env['SCRIPT_NAME'], env['PATH_INFO']]
    [200, { 'content-type' => 'text/plain' }, [body]]
  end
end

class BoardsController < Lux::Controller
  def root;    render text: 'boards:root';    end
  def new;     render text: 'boards:new';     end
  def archive; render text: 'boards:archive'; end

  ref do
    def show; render text: 'boards:show_ref'; end
    def edit; render text: 'boards:edit_ref'; end
  end
end

class ProfileController < Lux::Controller
  def root;  render text: 'profile:root'; end
  def edit;  render text: 'profile:edit'; end
end

class AdminTestController < Lux::Controller
  def root;  render text: 'admin:root:';  end
  def edit;  render text: 'admin:edit:';  end
  def users; render text: 'admin:users:'; end
  def foo;   render text: 'admin:foo:';   end

  ref do
    def show; render text: "admin:show_ref:#{nav.ref}"; end
    def edit; render text: "admin:edit_ref:#{nav.ref}"; end
    def foo;  render text: "admin:foo_ref:#{nav.ref}";  end
  end
end

###

Lux.app do
  after do
    if request.path == '/after-mutate'
      response.body { |b| b.gsub('hello', 'GREETINGS-FRIEND') }
    end
  end

  rescue_from do |err|
    call 'app_rescue_render#show'
  end

  before do
    # canonicalize ID-like segments to :ref before routing
    nav.path(:ref) { |el| el =~ /\A\d+\z/ ? el : nil }
  end

  root 'routes_test#root'

  map 'boards'
  map 'profile'
  map 'admin_test'

  map :plain => proc { lux.response.body 'plain' }
  map %r{^@} => [RoutesTestController, :user]
  map %r{^~} => RoutesTestController

  map 'city' do
    root 'routes_test#city'
    map user: 'routes_test#user'
  end

  map [:array1, :array2] => 'routes_test#root'

  map '/test1/test2/:foo' => 'routes_test#foo'

  map 'zagreb' => 'routes_test#city'

  map 'routes_test' do
    map 'foo-nested' => 'routes_test#nested'
  end

  map 'exploding' => 'exploding#boom'
  map 'exploding-via-call' => 'exploding#boom_via_call'
  map 'after-mutate' => 'after_mutate#show'

  # Rack-app dispatch: any class responding to .call(env) is routed via
  # `map`/`call` exactly like a controller.
  map '/r1'           => MountedRackApp     # absolute path
  map '/foo/bar/baz'  => MountedRackApp     # deep absolute path
  map r3:                MountedRackApp     # symbol shortcut (single segment)

  # Fallback 404 - this used to be a bare line inside `routes do` and ran on
  # every unmatched request. Wrap in a routes callback so it still fires last.
  routes { lux.response.body 'not found', status: 404 unless lux.response.body? }
end

###

describe 'Lux::Application' do
  it 'should get right routes' do
    _(Lux.render.get('/').body).must_equal 'root'
    _(Lux.render.get('/plain').body).must_equal 'plain'
    _(Lux.render.get('/@dux').body).must_equal 'user'
    # The legacy /~ regex map dispatched to RoutesTestController's :index when
    # there was no further segment. With the new :root default, that's `def root`
    # which already returns 'root'. So /~dux now hits :root.
    _(Lux.render.get('/~dux').body).must_equal 'root'
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

  it 'should render js route' do
    _(Lux.render.get('/routes_test/foo-nested.js').body[:a]).must_equal 1
  end

  it 'dispatches errors through Application rescue_from when defined (always wins)' do
    res = Lux.render.get('/exploding')
    _(res.status).must_equal 500
    _(res.body).must_equal 'APP-CATCH(500): BOOM!'
  end

  it 'rescue_from with `call` dispatches unconditionally' do
    res = Lux.render.get('/exploding-via-call')
    _(res.status).must_equal 500
    _(res.body).must_equal 'APP-CATCH(500): BOOM2'
  end

  it 'fires Application :after BEFORE headers, so content-length matches the mutated body' do
    res = Lux.render.get('/after-mutate')
    _(res.body).must_equal 'GREETINGS-FRIEND'
    _(res.headers['content-length']).must_equal 'GREETINGS-FRIEND'.bytesize.to_s
  end

  describe 'resourceful map (single segment controllers)' do
    it 'maps /boards (empty remaining) to :root' do
      _(Lux.render.get('/boards').body).must_equal 'boards:root'
    end

    it 'maps /boards/new to :new' do
      _(Lux.render.get('/boards/new').body).must_equal 'boards:new'
    end

    it 'maps /boards/123 (:ref only) to :show_ref' do
      _(Lux.render.get('/boards/123').body).must_equal 'boards:show_ref'
    end

    it 'maps /boards/123/edit to :edit_ref' do
      _(Lux.render.get('/boards/123/edit').body).must_equal 'boards:edit_ref'
    end

    it 'maps /boards/archive (single action segment) to that action' do
      _(Lux.render.get('/boards/archive').body).must_equal 'boards:archive'
    end

    it 'maps /profile (no further segment) to :root' do
      _(Lux.render.get('/profile').body).must_equal 'profile:root'
    end

    it 'maps /profile/edit to :edit' do
      _(Lux.render.get('/profile/edit').body).must_equal 'profile:edit'
    end
  end

  describe 'resourceful map action resolution' do
    it '/admin_test -> :root' do
      _(Lux.render.get('/admin_test').body).must_equal 'admin:root:'
    end

    it '/admin_test/edit -> :edit' do
      _(Lux.render.get('/admin_test/edit').body).must_equal 'admin:edit:'
    end

    it '/admin_test/123 -> :show_ref with nav.ref' do
      _(Lux.render.get('/admin_test/123').body).must_equal 'admin:show_ref:123'
    end

    it '/admin_test/123/edit -> :edit_ref with nav.ref' do
      _(Lux.render.get('/admin_test/123/edit').body).must_equal 'admin:edit_ref:123'
    end

    it '/admin_test/users -> :users (sub-resource as action)' do
      _(Lux.render.get('/admin_test/users').body).must_equal 'admin:users:'
    end

    it '/admin_test/users/123 -> :show_ref with nav.ref' do
      _(Lux.render.get('/admin_test/users/123').body).must_equal 'admin:show_ref:123'
    end

    it '/admin_test/users/123/edit -> :edit_ref with nav.ref' do
      _(Lux.render.get('/admin_test/users/123/edit').body).must_equal 'admin:edit_ref:123'
    end

    it '/admin_test/users/foo/bar -> :foo (trailing segment ignored, no :ref)' do
      _(Lux.render.get('/admin_test/users/foo/bar').body).must_equal 'admin:foo:'
    end

    it '/admin_test/users/123/foo/bar -> :foo_ref (has :ref, suffix applied)' do
      _(Lux.render.get('/admin_test/users/123/foo/bar').body).must_equal 'admin:foo_ref:123'
    end
  end
end
