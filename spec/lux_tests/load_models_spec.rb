require 'test_helper'

# load_models is the db plugin's Nav <-> model integration (a Nav reopening).
require File.expand_path('../../plugins/db/lib/ext/nav_models.rb', __dir__)

# Model stand-in carrying a 3-letter abbr.
RefProject ||= Struct.new(:ref) do
  def self.find(r); new(r); end
  def self.abbr; :pro; end
end

# Model without an abbr (matched by name only).
RefThingy ||= Struct.new(:ref) do
  def self.find(r); new(r); end
end

RefOrg ||= Struct.new(:ref) do
  def self.find(r); new(r); end
  def self.abbr; :org; end
end

# STI-style subclass: inherits RefProject's :pro abbr, keeps its own name.
class RefProjectPro < RefProject
  def self.find(r); new(r); end
end

# Nothing with this ref exists - find always 404s, like the real find_precache.
RefGhost ||= Struct.new(:ref) do
  def self.find(_r); raise Lux.error.not_found('gone'); end
  def self.abbr; :gho; end
end

describe 'Lux::Router::Nav#load_models' do
  REF1 ||= 'd' * 16

  # No nav.map_path here on purpose: load_models classifies refs itself.
  def nav_for path
    Lux::Context.new("http://example.com#{path}").nav
  end

  it 'matches the segment before the ref by abbr (/pro/<ref>)' do
    nav = nav_for "/foo/bar/pro/#{REF1}/baz"
    app = Object.new
    Lux.ctx.var[:lux_router] = app

    objects = nav.load_models RefProject

    _(objects.map(&:class)).must_equal [RefProject]
    _(app.instance_variable_get(:@object).ref).must_equal REF1
    _(app.instance_variable_get(:@ref_project).ref).must_equal REF1
  end

  it 'matches the segment before the ref by name (/ref_projects/<ref>)' do
    nav = nav_for "/ref_projects/#{REF1}"
    Lux.ctx.var[:lux_router] = Object.new
    _(nav.load_models(RefProject).first.ref).must_equal REF1
  end

  it 'matches the abbr:ref path-qs form (/foo/pro:REF)' do
    nav = nav_for "/foo/pro:#{REF1}"
    app = Object.new
    Lux.ctx.var[:lux_router] = app

    objects = nav.load_models RefProject
    _(objects.first.ref).must_equal REF1
    _(app.instance_variable_get(:@ref_project).ref).must_equal REF1
  end

  it 'skips candidates that do not define an abbr when matching by abbr' do
    nav = nav_for "/foo/pro:#{REF1}"
    Lux.ctx.var[:lux_router] = Object.new
    _(nav.load_models(RefThingy)).must_be_empty
  end

  describe 'driven by the path, not by the model list' do
    REF2 ||= 'e' * 16

    it 'resolves every ref in the URL, not just the first' do
      nav = nav_for "/ref_orgs/#{REF1}/ref_projects/#{REF2}/edit"
      app = Object.new
      Lux.ctx.var[:lux_router] = app

      objects = nav.load_models [RefOrg, RefProject]

      _(objects.map(&:class)).must_equal [RefOrg, RefProject]
      _(app.instance_variable_get(:@ref_org).ref).must_equal REF1
      _(app.instance_variable_get(:@ref_project).ref).must_equal REF2
    end

    it 'makes @object the deepest ref in the path' do
      nav = nav_for "/ref_orgs/#{REF1}/ref_projects/#{REF2}"
      app = Object.new
      Lux.ctx.var[:lux_router] = app
      nav.load_models [RefOrg, RefProject]

      _(app.instance_variable_get(:@object).ref).must_equal REF2
    end

    it 'ignores a ref whose owner segment names no model' do
      nav = nav_for "/unknown_things/#{REF1}"
      Lux.ctx.var[:lux_router] = Object.new
      _(nav.load_models(RefProject)).must_be_empty
    end

    it 'raises 404 for a ref whose record does not exist' do
      nav = nav_for "/ref_ghosts/#{REF1}/ref_projects/#{REF2}"
      Lux.ctx.var[:lux_router] = Object.new

      err = _{ nav.load_models [RefGhost, RefProject] }.must_raise Lux::Error
      _(err.status).must_equal 404
    end

    it 'treats - and _ as the same character in the owner segment' do
      nav = nav_for "/ref-projects/#{REF1}"
      Lux.ctx.var[:lux_router] = Object.new
      _(nav.load_models(RefProject).first.ref).must_equal REF1
    end

    it 'ignores a ref sitting directly behind another ref' do
      nav = nav_for "/ref_projects/#{REF1}/#{REF2}"
      Lux.ctx.var[:lux_router] = Object.new
      _(nav.load_models(RefProject).map(&:ref)).must_equal [REF1]
    end
  end

  describe 'abbr:ref path params' do
    REF3 ||= 'f' * 16

    it 'loads every abbr in the URL (/pro:<r1>/org:<r2>)' do
      nav = nav_for "/foo/pro:#{REF1}/org:#{REF3}"
      app = Object.new
      Lux.ctx.var[:lux_router] = app

      objects = nav.load_models [RefProject, RefOrg]

      _(objects.map(&:class).sort_by(&:to_s)).must_equal [RefOrg, RefProject]
      _(app.instance_variable_get(:@ref_project).ref).must_equal REF1
      _(app.instance_variable_get(:@ref_org).ref).must_equal REF3
    end

    it 'is skipped entirely with pqs: false' do
      nav = nav_for "/foo/pro:#{REF1}/org:#{REF3}"
      Lux.ctx.var[:lux_router] = Object.new
      _(nav.load_models([RefProject, RefOrg], pqs: false)).must_be_empty
    end

    it 'does not let a nested form hash reach find' do
      nav = nav_for '/foo'
      Lux.ctx.var[:lux_router] = Object.new
      Lux.ctx.params[:pro] = { 'name' => 'x' }

      _(nav.load_models(RefProject)).must_be_empty
    end

    # Pro < User in vibe: both answer :usr, and Sequel lists the subclass first
    it 'gives a contested abbr to the base class, not the STI subclass' do
      nav = nav_for "/foo/pro:#{REF1}"
      app = Object.new
      Lux.ctx.var[:lux_router] = app

      nav.load_models [RefProjectPro, RefProject]

      _(app.instance_variable_get(:@ref_project).ref).must_equal REF1
      _(app.instance_variable_get(:@ref_project_pro)).must_be_nil
    end

    it 'still reaches the subclass by its own name' do
      nav = nav_for "/ref_project_pros/#{REF1}"
      app = Object.new
      Lux.ctx.var[:lux_router] = app

      nav.load_models [RefProjectPro, RefProject]

      _(app.instance_variable_get(:@ref_project_pro).ref).must_equal REF1
    end

    it 'lets the path win when both name the same model' do
      nav = nav_for "/ref_projects/#{REF1}/pro:#{REF3}"
      app = Object.new
      Lux.ctx.var[:lux_router] = app
      nav.load_models RefProject

      _(app.instance_variable_get(:@ref_project).ref).must_equal REF1
    end
  end
end
