require 'test_helper'

# Tests for per-action `route` annotations defined on controllers and
# resolved by Lux::Application#resolve_action_routes. Hits the same render
# pipeline as routes_spec via Lux.render.get / .post, so the spec needs
# config defaults that Lux.boot! would normally set.
%i(serve_static_files use_autoroutes asset_root deploy_timestamp csrf).each do |k|
  Lux.config[k] = false unless Lux.config.key?(k)
end
Lux.config[:plugins] ||= []
Lux.config[:logger_path_mask]     = './log/%s.log' unless Lux.config.key?(:logger_path_mask)
Lux.config[:logger_files_to_keep] = 3              unless Lux.config.key?(:logger_files_to_keep)
Lux.config[:logger_file_max_size] = 10_240_000     unless Lux.config.key?(:logger_file_max_size)
Lux.config[:logger_formatter]     = nil            unless Lux.config.key?(:logger_formatter)

# Tracks whether before-filter ran before route resolution (and what it set).
$action_route_spec_before_ran = nil

class RouteAnnotationController < Lux::Controller
  route '/ra/list'
  def index
    render text: 'list'
  end

  route '/ra/u/:slug'
  def by_slug
    render text: 'by_slug:%s' % params[:slug]
  end

  route '/ra/items/:ref'
  def show
    render text: 'show:%s' % nav.ref
  end

  # alias stacking - both URLs hit the same action
  route '/ra/create'
  route '/ra/new'
  allow :get, :post
  def create
    render text: 'create:%s' % lux.request.request_method
  end

  # POST-only via allow
  route '/ra/post-only'
  allow :post
  def post_only
    render text: 'post_only:%s' % lux.request.request_method
  end

  # ref-block placement: method gets _ref suffix; route still resolves
  ref do
    route '/ra/members/:ref/dashboard'
    def dashboard
      render text: 'dashboard:%s:via_%s' % [nav.ref, $action_route_spec_before_ran || 'nil']
    end
  end
end

# Resourceful map exists at /ra-fallback for non-route paths.
class RaFallbackController < Lux::Controller
  def root
    render text: 'fallback-root'
  end
end

Lux.app do
  before do
    $action_route_spec_before_ran = 'before-filter'
  end

  map 'ra-fallback', 'ra_fallback'
  # No global `routes { 404 }` fallback here on purpose - Lux's default
  # 404 handler covers the `/totally-not-mapped` test below, and any
  # custom fallback would clobber routes_spec's maps (loads after this).
end

###

describe 'Lux::Controller per-action routes' do
  before do
    $action_route_spec_before_ran = nil
  end

  describe 'class-level DSL' do
    it 'registers an entry per route line in Lux::Controller.action_routes' do
      paths = Lux::Controller.action_routes
        .select { |e| e[:controller] == RouteAnnotationController }
        .map { |e| e[:path] }
      _(paths).must_include '/ra/list'
      _(paths).must_include '/ra/u/:slug'
      _(paths).must_include '/ra/items/:ref'
      _(paths).must_include '/ra/create'
      _(paths).must_include '/ra/new'
    end

    it 'snapshots routes per def, like opt/allow' do
      store = RouteAnnotationController.instance_variable_get(:@_action_routes)
      _(store.key?(:index)).must_equal true
      _(store[:create].map(&:first)).must_equal ['/ra/create', '/ra/new']
    end

    it 'raises ArgumentError for relative paths' do
      err = _{
        Class.new(Lux::Controller) do
          route 'bogus'
        end
      }.must_raise ArgumentError
      _(err.message).must_match(/must be a String starting with/)
    end
  end

  describe 'dispatch' do
    it 'matches a literal path' do
      _(Lux.render.get('/ra/list').body).must_equal 'list'
    end

    it 'matches a single capture and binds nav.params' do
      _(Lux.render.get('/ra/u/coolslug').body).must_equal 'by_slug:coolslug'
    end

    it 'binds :ref capture to nav.ref' do
      _(Lux.render.get('/ra/items/abc123').body).must_equal 'show:abc123'
    end

    it 'dispatches the same action for each stacked route line' do
      _(Lux.render.get('/ra/create').body).must_equal 'create:GET'
      _(Lux.render.get('/ra/new').body).must_equal 'create:GET'
    end

    it 'requires length-exact matching (extra segment 404s)' do
      _(Lux.render.get('/ra/items/abc/extra').status).must_equal 404
    end

    it 'falls through to routes do for non-matching paths' do
      _(Lux.render.get('/ra-fallback').body).must_equal 'fallback-root'
    end

    it 'falls through to the 404 callback for unknown paths' do
      _(Lux.render.get('/totally-not-mapped').status).must_equal 404
    end
  end

  describe 'verb enforcement (allow + route combine)' do
    it 'accepts POST when allow :post is declared' do
      _(Lux.render.post('/ra/post-only').body).must_equal 'post_only:POST'
    end

    it 'rejects GET on a POST-only routed action with 405' do
      _(Lux.render.get('/ra/post-only').status).must_equal 405
    end

    it 'accepts both verbs when allow :get, :post is declared' do
      _(Lux.render.get('/ra/create').body).must_equal 'create:GET'
      _(Lux.render.post('/ra/create').body).must_equal 'create:POST'
    end
  end

  describe 'ref do interaction' do
    it 'still renames the method to _ref' do
      _(RouteAnnotationController.instance_methods(false)).must_include :dashboard_ref
      refute_includes RouteAnnotationController.instance_methods(false), :dashboard
    end

    it 'dispatches the :ref-renamed action via the declared route' do
      _(Lux.render.get('/ra/members/m42/dashboard').body)
        .must_equal 'dashboard:m42:via_before-filter'
    end

    it 'remaps the registry entry to the _ref action key' do
      entry = Lux::Controller.action_routes
        .detect { |e| e[:controller] == RouteAnnotationController && e[:path] == '/ra/members/:ref/dashboard' }
      _(entry[:action]).must_equal :dashboard_ref
    end
  end

  describe 'before-filter ordering' do
    it 'runs application before-filter prior to route dispatch' do
      Lux.render.get('/ra/members/m42/dashboard')
      _($action_route_spec_before_ran).must_equal 'before-filter'
    end
  end

  describe 'Application.dump_routes integration' do
    it 'includes per-action route entries with [action-route] tag' do
      dump = Lux::Application.dump_routes
      entry = dump.detect { |e| e.path == '/ra/list' }
      refute_nil entry
      _(entry.target).must_include 'RouteAnnotationController#index'
      _(entry.target).must_include '[action-route]'
    end

    it 'shows the joined allowed verbs for the action' do
      dump  = Lux::Application.dump_routes
      entry = dump.detect { |e| e.path == '/ra/post-only' }
      _(entry.verb).must_equal 'POST'
    end
  end
end
