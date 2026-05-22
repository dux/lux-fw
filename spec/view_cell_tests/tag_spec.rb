require 'spec_helper'

###

class HtmlTagCell < Lux::ViewCell
  before do
    @num = 123
  end

  def foo
    tag.ol do
      li do
        a @num, href: '#'
      end
    end
  end
end

###

describe 'Lux::ViewCell tag' do
  it 'renders' do
    expect(HtmlTagCell.new.foo).to eq('<ol><li><a href="#">123</a></li></ol>')
  end
end
