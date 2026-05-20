require 'spec_helper'

###

class TplCell < Lux::ViewCell
  template_root './assets/view_cell/spec/views/%s'

  css 'foo.scss'

  def foo
    @num = 3
    template 'tpl/base'
  end
end

###

describe 'Lux::ViewCell tpl' do
  before do
    TplCell.template_root './assets/view_cell/spec/views'
  end

  it 'compiles css defined in custom template root' do
    css = TplCell.css
    # foo.scss compiles to a block containing "#foo" and "color: yellow"
    expect(css).to include('#foo')
    expect(css).to include('color: yellow')
  end

  it 'compiles template defined in custom template root' do
    data = TplCell.new.foo
    expect(data).to eq('x9x')
  end

  it 'raises when template not found in alternate root' do
    TplCell.template_root './spec/x_views'
    expect { TplCell.new.foo }.to raise_error(ArgumentError, %[Template "./spec/x_views/tpl/base.*" not found])
  end
end
