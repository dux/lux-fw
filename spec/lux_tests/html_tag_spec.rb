require 'spec_helper'

describe 'Lux::Utils::HtmlTag' do
  it 'is the same object as the top-level HtmlTag constant' do
    expect(::HtmlTag).to be(Lux::Utils::HtmlTag)
  end

  it 'renders via the namespaced proxy form' do
    out = HtmlTag.div(class: 'x') { |n| n.span 'hi' }
    expect(out).to eq('<div class="x"><span>hi</span></div>')
  end

  it 'renders via the top-level alias' do
    out = HtmlTag.p('hello')
    expect(out).to eq('<p>hello</p>')
  end

  it 'renders via HtmlTag.call(:tag) { ... }' do
    out = HtmlTag.call(:ul) do |n|
      n.li 'a'
      n.li 'b'
    end
    expect(out).to eq('<ul><li>a</li><li>b</li></ul>')
  end

  it 'installs Hash#tag' do
    expect({ class: 'btn' }.tag(:button, 'Save')).to eq('<button class="btn">Save</button>')
  end

  it 'installs String#tag' do
    expect('hi'.tag(:span)).to eq('<span>hi</span>')
  end

  it 'injects `tag` as a class-method mixin via HtmlTag.mixin(self)' do
    klass = Class.new do
      HtmlTag.mixin(self)
      def render
        tag.div(class: 'card') { b 'x' }
      end
    end

    expect(klass.new.render).to eq('<div class="card"><b>x</b></div>')
  end

  it 'supports include HtmlTag' do
    klass = Class.new do
      include HtmlTag
      def render
        tag.section { span '1' }
      end
    end

    expect(klass.new.render).to eq('<section><span>1</span></section>')
  end

  it 'supports custom tag registration' do
    HtmlTag.define :duxtag
    expect(HtmlTag.duxtag('y')).to eq('<duxtag>y</duxtag>')
  end

  it 'supports custom empty/void tag registration' do
    HtmlTag.define :voidtag, empty: true
    expect(HtmlTag.voidtag).to eq('<voidtag />')
  end

  it 'expands underscore-prefixed name as a div+class shortcut' do
    expect(HtmlTag._search_filter).to eq('<div class="search-filter"></div>')
    expect(HtmlTag._card__lead { 'x' }).to eq('<div class="card lead">x</div>')
  end

  it 'merges shortcut classes with an explicit :class kwarg' do
    expect(HtmlTag._card(class: 'extra') { 'y' }).to eq('<div class="card extra">y</div>')
  end
end
