require 'test_helper'

# Throwaway Router subclasses so we don't pollute Lux.router for other specs.
class DumpAdminRouter < Lux::Router
  route do
    map 'users', 'dump_admin_users'
    auto
  end
end

class DumpRouter < Lux::Router
  before { 1 }   # should not appear in the dump

  route do
    root 'dump_main#index'
    map 'about', 'static#about'
    map 'boards', 'dump_boards'        # router name without a route block
    map 'logout', :logout              # action on this router
    map 'admin', DumpAdminRouter       # router with a route block - replayed in place
    map :spaces, :ref, :admin do
      auto
    end
    map '/abs/:id', 'main#show'

    # conditional via http-method predicate: should still be visible in dump
    get? { map 'preview', 'main#preview' }

    map 'reports#monthly'              # unconditional dispatch
  end
end

# Routes that read the current URL while the dump replays them.
class DumpUrlRouter < Lux::Router
  route do
    redirect_to nav.subdomain('app') if params[:login]
    map 'after-url', 'main#after_url'
  end
end

describe Lux::Router::RoutesDumper do
  def entries
    @entries ||= DumpRouter.dump_routes
  end

  def at path
    entries.select { |x| x.path == path }.map(&:target)
  end

  it 'records the root route' do
    _(at('/')).must_include 'dump_main#index'
  end

  it 'records simple map with explicit target' do
    _(at('/about')).must_equal ['static#about']
  end

  it 'records a router name at its own segment' do
    _(at('/boards')).must_equal ['dump_boards']
  end

  it 'records a Symbol target as an action' do
    _(at('/logout')).must_equal ['#logout']
  end

  it 'replays a mounted router route under its segment' do
    _(at('/admin/users')).must_equal ['dump_admin_users']
    _(at('/admin')).must_equal ['[auto]']
  end

  it 'records segment chains, with :ref kept as a placeholder' do
    _(at('/spaces/:ref/admin')).must_equal ['[auto]']
  end

  it 'records an unconditional map at the current path' do
    _(at('/')).must_include 'reports#monthly'
  end

  it 'records absolute-path match form' do
    _(at('/abs/:id')).must_equal ['main#show']
  end

  it 'records http-method-scoped routes with the right verb' do
    e = entries.find { |x| x.path == '/preview' }
    _(e).wont_be_nil
    _(e.verb).must_equal 'GET'
  end

  it 'survives Url helpers inside the route block' do
    _(DumpUrlRouter.dump_routes.map(&:path)).must_include '/after-url'
  end

  it 'records the source of the route block each entry came from' do
    refute_empty entries
    entries.each do |entry|
      assert_match %r{routes_dumper_spec\.rb}, entry.source.to_s
    end
  end
end
