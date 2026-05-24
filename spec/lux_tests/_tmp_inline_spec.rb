require 'test_helper'

describe Lux::Error do
  before do
    Lux::Current.new('http://testing/widgets?x=1')
    @original_debug = Lux.mode.method(:debug?)
    Lux.mode.define_singleton_method(:debug?) { |short = nil, &blk| blk ? blk.call : true }
  end

  after do
    original = @original_debug
    Lux.mode.define_singleton_method(:debug?) { |*a, &b| original.call(*a, &b) }
  end

  it 'inline output contains URL, Copy btn, hidden textarea' do
    error = StandardError.new('boom <bad>')
    error.set_backtrace(["#{Lux.root}/app/foo.rb:1:in `bar'"])
    html = Lux::Error.inline(error)
    _(html).must_include 'URL: '
    _(html).must_include 'class="btn"'
    _(html).must_include '<textarea'
    _(html).must_include 'navigator.clipboard.writeText'
  end
end
