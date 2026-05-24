require 'test_helper'

###

class TplCell < Lux::ViewCell
  template_root './spec/view_cell_tests/views/%s'

  css 'foo.scss'

  def foo
    @num = 3
    template 'tpl/base'
  end
end

###

describe 'Lux::ViewCell tpl' do
  before do
    TplCell.template_root './spec/view_cell_tests/views'
  end

  it 'compiles css defined in custom template root' do
    css = TplCell.css
    # foo.scss compiles to a block containing "#foo" and "color: yellow"
    _(css).must_include '#foo'
    _(css).must_include 'color: yellow'
  end

  it 'compiles template defined in custom template root' do
    data = TplCell.new.foo
    _(data).must_equal 'x9x'
  end

  it 'raises when template not found in alternate root' do
    TplCell.template_root './spec/x_views'
    _{ TplCell.new.foo }.must_raise ArgumentError
  end
end
