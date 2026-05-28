require 'test_helper'

# load_models lives in the db plugin's pure-Ruby ref.rb (a Nav reopening).
require File.expand_path('../../plugins/db/lib/ref.rb', __dir__)

# Model stand-in carrying a 3-letter abbr.
RefProject ||= Struct.new(:ref) do
  def self.find(r); new(r); end
  def self.abbr; :pro; end
end

# Model without an abbr (matched by name only).
RefThingy ||= Struct.new(:ref) do
  def self.find(r); new(r); end
end

describe 'Lux::Application::Nav#load_models' do
  REF1 ||= 'd' * 16

  def nav_for path
    Lux::Current.new("http://example.com#{path}").nav.tap(&:extract_ref!)
  end

  it 'matches the segment before the ref by abbr (/pro/<ref>)' do
    nav = nav_for "/foo/bar/pro/#{REF1}/baz"
    app = Object.new
    Lux.current.var[:lux_app] = app

    objects = nav.load_models RefProject

    _(objects.map(&:class)).must_equal [RefProject]
    _(app.instance_variable_get(:@object).ref).must_equal REF1
    _(app.instance_variable_get(:@ref_project).ref).must_equal REF1
  end

  it 'matches the segment before the ref by name (/ref_projects/<ref>)' do
    nav = nav_for "/ref_projects/#{REF1}"
    Lux.current.var[:lux_app] = Object.new
    _(nav.load_models(RefProject).first.ref).must_equal REF1
  end

  it 'matches the abbr:ref path-qs form (/foo/pro:REF)' do
    nav = nav_for "/foo/pro:#{REF1}"
    app = Object.new
    Lux.current.var[:lux_app] = app

    objects = nav.load_models RefProject
    _(objects.first.ref).must_equal REF1
    _(app.instance_variable_get(:@ref_project).ref).must_equal REF1
  end

  it 'skips candidates that do not define an abbr when matching by abbr' do
    nav = nav_for "/foo/pro:#{REF1}"
    Lux.current.var[:lux_app] = Object.new
    _(nav.load_models(RefThingy)).must_be_empty
  end
end
