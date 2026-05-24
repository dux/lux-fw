require 'test_helper'
require_relative '../loader'

describe 'annotations' do
  it 'tests custom annotation' do
    _(GenericApi.render.anon_test[:data]).must_equal 12345
  end
end
