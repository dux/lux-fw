require 'test_helper'

# ref_object lives in the db plugin's pure-Ruby ref.rb (a Nav reopening).
require File.expand_path('../../plugins/db/lib/ref.rb', __dir__)

RefWidget ||= Struct.new(:ref) { def self.find(r); new(r); end }

describe 'Lux::Application::Nav#ref_object' do
  WIDGET_REF ||= 'c' * 16

  def nav_for path
    Lux::Current.new("http://example.com#{path}").nav.tap(&:extract_ref!)
  end

  it 'loads the model named by the segment before the ref, not path[0]' do
    nav = nav_for "/foo/bar/ref_widgets/#{WIDGET_REF}/baz"
    app = Object.new
    Lux.current.var[:lux_app] = app

    object = nav.ref_object

    _(object.class).must_equal RefWidget
    _(object.ref).must_equal WIDGET_REF
    _(app.instance_variable_get(:@object).ref).must_equal WIDGET_REF
    _(app.instance_variable_get(:@ref_widget).ref).must_equal WIDGET_REF
  end

  it 'returns nil when the path carries no ref' do
    nav = nav_for '/dashboard'
    Lux.current.var[:lux_app] = Object.new
    _(nav.ref_object).must_be_nil
  end
end
