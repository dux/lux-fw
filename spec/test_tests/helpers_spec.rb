require 'test_helper'

describe 'Lux::Test helpers' do
  it 'capture_log returns what Lux.logger wrote' do
    out = capture_log { Lux.logger.error 'captured-line' }
    _(out).must_match(/captured-line/)
  end

  it 'assert_redirect nil passes when there is no redirect' do
    resp = Struct.new(:redirect_to).new(nil)
    assert_redirect nil, resp
  end

  it 'assert_json_includes matches nil and false values' do
    assert_json_includes({ error: nil, ok: false }, { 'ok' => false })
  end
end
