require 'test_helper'

describe Lux::Error do
  before do
    Lux::Current.new('http://testing/widgets?x=1')
    @prev_debug = Lux.debug?
    Lux.debug = true
  end

  after do
    Lux.debug = @prev_debug
  end

  it 'inline output contains URL, Copy btn, hidden textarea' do
    error = StandardError.new('boom <bad>')
    error.set_backtrace(["#{Lux.root}/app/foo.rb:1:in `bar'"])
    html = Lux::Error.inline(error)
    _(html).must_include 'URL: '
    _(html).must_include 'class="btn"'
    _(html).must_include '<textarea'
    _(html).must_include '$.copyText'
  end
end
