require 'spec_helper'

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
    def show; render text: "admin:show_ref:#{nav.id}"; end
    def edit; render text: "admin:edit_ref:#{nav.id}"; end
    def foo;  render text: "admin:foo_ref:#{nav.id}";  end
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

  # Fallback 404 - this used to be a bare line inside `routes do` and ran on
  # every unmatched request. Wrap in a routes callback so it still fires last.
  routes { lux.response.body 'not found', status: 404 unless lux.response.body? }
end

###

describe Lux::Application do
  it 'should get right routes' do
    expect(Lux.render.get('/').body).to  eq 'root'
    expect(Lux.render.get('/plain').body).to eq 'plain'
    expect(Lux.render.get('/@dux').body).to  eq 'user'
    # The legacy /~ regex map dispatched to RoutesTestController's :index when
    # there was no further segment. With the new :root default, that's `def root`
    # which already returns 'root'. So /~dux now hits :root.
    expect(Lux.render.get('/~dux').body).to  eq 'root'
  end

  it 'should get nested routes' do
    expect(Lux.render.get('/test1/test2/bar').body).to eq 'bar'
    expect(Lux.render.get('/routes_test/foo-nested').body).to eq 'nested'
  end

  it 'should get list routes' do
    expect(Lux.render.get('/array1').body).to eq 'root'
    expect(Lux.render.get('/array2').body).to eq 'root'
  end

  it 'should get namespace routes' do
    expect(Lux.render.get('/zagreb').body).to eq 'zagreb'
    expect(Lux.render.get('/city').body).to eq 'zagreb'
    expect(Lux.render.get('/city/user').body).to eq 'user'
  end

  it 'should get bad routes' do
    expect(Lux.render.get('/not-found').status).to eq 404
    expect(Lux.render.get('/x@dux').status).to eq 404
  end

  it 'should render js route' do
    expect(Lux.render.get('/routes_test/foo-nested.js').body[:a]).to eq(1)
  end

  it 'dispatches errors through Application rescue_from when defined (always wins)' do
    res = Lux.render.get('/exploding')
    expect(res.status).to eq(500)
    expect(res.body).to eq('APP-CATCH(500): BOOM!')
  end

  it 'rescue_from with `call` dispatches unconditionally' do
    res = Lux.render.get('/exploding-via-call')
    expect(res.status).to eq(500)
    expect(res.body).to eq('APP-CATCH(500): BOOM2')
  end

  it 'fires Application :after BEFORE headers, so content-length matches the mutated body' do
    res = Lux.render.get('/after-mutate')
    expect(res.body).to eq('GREETINGS-FRIEND')
    expect(res.headers['content-length']).to eq('GREETINGS-FRIEND'.bytesize.to_s)
  end

  describe 'resourceful map (single segment controllers)' do
    it 'maps /boards (empty remaining) to :root' do
      expect(Lux.render.get('/boards').body).to eq('boards:root')
    end

    it 'maps /boards/new to :new' do
      expect(Lux.render.get('/boards/new').body).to eq('boards:new')
    end

    it 'maps /boards/123 (:ref only) to :show_ref' do
      expect(Lux.render.get('/boards/123').body).to eq('boards:show_ref')
    end

    it 'maps /boards/123/edit to :edit_ref' do
      expect(Lux.render.get('/boards/123/edit').body).to eq('boards:edit_ref')
    end

    it 'maps /boards/archive (single action segment) to that action' do
      expect(Lux.render.get('/boards/archive').body).to eq('boards:archive')
    end

    it 'maps /profile (no further segment) to :root' do
      expect(Lux.render.get('/profile').body).to eq('profile:root')
    end

    it 'maps /profile/edit to :edit' do
      expect(Lux.render.get('/profile/edit').body).to eq('profile:edit')
    end
  end

  describe 'resourceful map action resolution' do
    it '/admin_test -> :root' do
      expect(Lux.render.get('/admin_test').body).to eq('admin:root:')
    end

    it '/admin_test/edit -> :edit' do
      expect(Lux.render.get('/admin_test/edit').body).to eq('admin:edit:')
    end

    it '/admin_test/123 -> :show_ref with nav.id' do
      expect(Lux.render.get('/admin_test/123').body).to eq('admin:show_ref:123')
    end

    it '/admin_test/123/edit -> :edit_ref with nav.id' do
      expect(Lux.render.get('/admin_test/123/edit').body).to eq('admin:edit_ref:123')
    end

    it '/admin_test/users -> :users (sub-resource as action)' do
      expect(Lux.render.get('/admin_test/users').body).to eq('admin:users:')
    end

    it '/admin_test/users/123 -> :show_ref with nav.id' do
      expect(Lux.render.get('/admin_test/users/123').body).to eq('admin:show_ref:123')
    end

    it '/admin_test/users/123/edit -> :edit_ref with nav.id' do
      expect(Lux.render.get('/admin_test/users/123/edit').body).to eq('admin:edit_ref:123')
    end

    it '/admin_test/users/foo/bar -> :foo (trailing segment ignored, no :ref)' do
      expect(Lux.render.get('/admin_test/users/foo/bar').body).to eq('admin:foo:')
    end

    it '/admin_test/users/123/foo/bar -> :foo_ref (has :ref, suffix applied)' do
      expect(Lux.render.get('/admin_test/users/123/foo/bar').body).to eq('admin:foo_ref:123')
    end
  end
end
