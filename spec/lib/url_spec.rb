require 'spec_helper'

describe Url do
  it 'shold generate url' do
    u = Url.new('https://www.YouTube.com/watch?t=1260&v=cOFSX6nezEY')
    u.delete :t
    u.hash '160s'
    expect(u.to_s).to eq('https://www.youtube.com/watch?v=cOFSX6nezEY#160s')
  end

  it 'should read request' do
    Lux::Current.prepare 'http://www.lvh.com/abc?def=123'
    expect(Url.current.qs('abc','456').to_s).to eq('http://www.lvh.com/abc?abc=456&def=123')
  end
end