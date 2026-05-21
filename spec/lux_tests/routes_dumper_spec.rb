require 'spec_helper'

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
  let(:entries) { DumpApp.dump_routes }

  it 'records the root route' do
    e = entries.find { |x| x.path == '/' }
    expect(e).not_to be_nil
    expect(e.target).to eq('main')
  end

  it 'records simple map with explicit target' do
    e = entries.find { |x| x.path == '/about' }
    expect(e).not_to be_nil
    expect(e.target).to eq('static#about')
  end

  it 'records nested map block as joined path' do
    paths = entries.map(&:path)
    expect(paths).to include('/admin/users')
  end

  it 'records absolute-path match form' do
    e = entries.find { |x| x.path == '/abs/:id' }
    expect(e).not_to be_nil
    expect(e.target).to eq('main#show')
  end

  it 'records http-method-scoped routes with the right verb' do
    e = entries.find { |x| x.path == '/preview' }
    expect(e).not_to be_nil
    expect(e.verb).to eq('GET')
  end

  it 'records source location on each entry' do
    expect(entries).to all(have_attributes(source: a_string_matching(%r{routes_dumper_spec\.rb}) ))
  end
end
