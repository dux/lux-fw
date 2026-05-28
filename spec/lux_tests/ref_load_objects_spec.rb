require 'test_helper'

# ref_load_objects lives in the db plugin's pure-Ruby ref.rb (a Nav reopening).
# Require it directly so the test stays off the Sequel/Postgres stack.
require File.expand_path('../../plugins/db/lib/ref.rb', __dir__)

# Minimal model stand-ins: find(ref) returns an instance carrying that ref.
RefOrg  ||= Struct.new(:ref) { def self.find(ref); new(ref); end }
RefUser ||= Struct.new(:ref) { def self.find(ref); new(ref); end }

describe 'Lux::Application::Nav#ref_load_objects' do
  ORG_REF  ||= 'a' * 16
  USER_REF ||= 'b' * 16

  def nav_for path
    Lux::Current.new("http://example.com#{path}").nav.tap(&:extract_ref!)
  end

  it 'maps classes to refs by position and returns the loaded objects' do
    nav     = nav_for "/orgs/#{ORG_REF}/users/#{USER_REF}"
    objects = nav.ref_load_objects RefOrg, RefUser
    _(objects.map(&:class)).must_equal [RefOrg, RefUser]
    _(objects.map(&:ref)).must_equal [ORG_REF, USER_REF]
  end

  it 'runs the block once per loaded object' do
    nav  = nav_for "/orgs/#{ORG_REF}/users/#{USER_REF}"
    seen = []
    nav.ref_load_objects(RefOrg, RefUser) { |o| seen << o.ref }
    _(seen).must_equal [ORG_REF, USER_REF]
  end

  it 'exports ivars on the running app instance with ivars: true' do
    nav = nav_for "/orgs/#{ORG_REF}/users/#{USER_REF}"
    app = Object.new
    Lux.current.var[:lux_app] = app
    nav.ref_load_objects RefOrg, RefUser, ivars: true
    _(app.instance_variable_get(:@ref_org).ref).must_equal ORG_REF
    _(app.instance_variable_get(:@ref_user).ref).must_equal USER_REF
  end

  it 'does not export ivars without the flag' do
    nav = nav_for "/orgs/#{ORG_REF}/users/#{USER_REF}"
    app = Object.new
    Lux.current.var[:lux_app] = app
    nav.ref_load_objects RefOrg, RefUser
    _(app.instance_variables).must_be_empty
  end

  it 'returns nil for a class without a matching ref, without raising' do
    nav     = nav_for "/orgs/#{ORG_REF}"
    objects = nav.ref_load_objects RefOrg, RefUser
    _(objects[0].ref).must_equal ORG_REF
    _(objects[1]).must_be_nil
  end
end
