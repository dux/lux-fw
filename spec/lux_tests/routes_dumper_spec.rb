require 'test_helper'

# A throwaway Application subclass so we don't pollute Lux.app for other specs.
class DumpApp < Lux::Application
  before { 1 }   # should not appear in the dump

  root 'main'
  map about: 'static#about'
  map 'admin' do
    root 'admin/dashboard'
    map users: 'admin/users'
  end
  map '/abs/:id' => 'main#show'

  # conditional via http-method predicate: should still be visible in dump
  get? { map 'preview' => 'main#preview' }
end

describe Lux::Application::RoutesDumper do
  def entries
    @entries ||= DumpApp.dump_routes
  end

  it 'records the root route' do
    e = entries.find { |x| x.path == '/' }
    _(e).wont_be_nil
    _(e.target).must_equal 'main'
  end

  it 'records simple map with explicit target' do
    e = entries.find { |x| x.path == '/about' }
    _(e).wont_be_nil
    _(e.target).must_equal 'static#about'
  end

  it 'records nested map block as joined path' do
    paths = entries.map(&:path)
    _(paths).must_include '/admin/users'
  end

  it 'records absolute-path match form' do
    e = entries.find { |x| x.path == '/abs/:id' }
    _(e).wont_be_nil
    _(e.target).must_equal 'main#show'
  end

  it 'records http-method-scoped routes with the right verb' do
    e = entries.find { |x| x.path == '/preview' }
    _(e).wont_be_nil
    _(e.verb).must_equal 'GET'
  end

  it 'records source location on each entry' do
    refute_empty entries
    entries.each do |entry|
      assert_match %r{routes_dumper_spec\.rb}, entry.source.to_s
    end
  end
end
