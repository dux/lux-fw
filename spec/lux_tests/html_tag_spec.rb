require 'test_helper'

describe 'Lux::Utils::HtmlTag' do
  it 'is the same object as the top-level HtmlTag constant' do
    _(::HtmlTag).must_equal Lux::Utils::HtmlTag
  end

  it 'renders via the namespaced proxy form' do
    out = HtmlTag.div(class: 'x') { |n| n.span 'hi' }
    _(out).must_equal '<div class="x"><span>hi</span></div>'
  end

  it 'renders via the top-level alias' do
    out = HtmlTag.p('hello')
    _(out).must_equal '<p>hello</p>'
  end

  it 'renders via HtmlTag.call(:tag) { ... }' do
    out = HtmlTag.call(:ul) do |n|
      n.li 'a'
      n.li 'b'
    end
    _(out).must_equal '<ul><li>a</li><li>b</li></ul>'
  end

  it 'installs Hash#tag' do
    _({ class: 'btn' }.tag(:button, 'Save')).must_equal '<button class="btn">Save</button>'
  end

  it 'installs String#tag' do
    _('hi'.tag(:span)).must_equal '<span>hi</span>'
  end

  it 'injects `tag` as a class-method mixin via HtmlTag.mixin(self)' do
    klass = Class.new do
      HtmlTag.mixin(self)
      def render
        tag.div(class: 'card') { b 'x' }
      end
    end

    _(klass.new.render).must_equal '<div class="card"><b>x</b></div>'
  end

  it 'supports include HtmlTag' do
    klass = Class.new do
      include HtmlTag
      def render
        tag.section { span '1' }
      end
    end

    _(klass.new.render).must_equal '<section><span>1</span></section>'
  end

  it 'supports custom tag registration' do
    HtmlTag.define :duxtag
    _(HtmlTag.duxtag('y')).must_equal '<duxtag>y</duxtag>'
  end

  it 'supports custom empty/void tag registration' do
    HtmlTag.define :voidtag, empty: true
    _(HtmlTag.voidtag).must_equal '<voidtag />'
  end

  it 'expands underscore-prefixed name as a div+class shortcut' do
    _(HtmlTag._search_filter).must_equal '<div class="search-filter"></div>'
    _(HtmlTag._card__lead { 'x' }).must_equal '<div class="card lead">x</div>'
  end

  it 'merges shortcut classes with an explicit :class kwarg' do
    _(HtmlTag._card(class: 'extra') { 'y' }).must_equal '<div class="card extra">y</div>'
  end

  it 'treats a second-positional Hash as attrs, not inner content' do
    out = HtmlTag.call('ui-favorite', { key: 'User/abc', exists: false })
    _(out).must_equal '<ui-favorite key="User/abc" exists="false"></ui-favorite>'
  end
end
