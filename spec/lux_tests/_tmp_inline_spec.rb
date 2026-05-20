require 'spec_helper'

describe Lux::Error do
  before { Lux::Current.new('http://testing/widgets?x=1') }

  it 'inline output contains URL, Copy btn, hidden textarea' do
    allow(Lux.mode).to receive(:errors?).and_return(true)
    error = StandardError.new('boom <bad>')
    error.set_backtrace(["#{Lux.root}/app/foo.rb:1:in `bar'"])
    html = Lux::Error.inline(error)
    puts '---START---'
    puts html
    puts '---END---'
    expect(html).to include('URL: ')
    expect(html).to include('class="btn"')
    expect(html).to include('<textarea')
    expect(html).to include('navigator.clipboard.writeText')
  end
end
