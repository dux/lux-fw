require 'test_helper'
require_relative '../loader'

describe 'annotations' do
  it 'tests custom annotation' do
    _(GenericApi.render.anon_test[:data]).must_equal 12345
  end

  it 'keeps a trailing unsafe on its own class' do
    Class.new(Lux::Api) { unsafe }
    other = Class.new(Lux::Api) do
      define(:leak_check) { proc { 1 } }
    end

    assert_nil other.get(:collection, :leak_check, :unsafe)
  end
end
