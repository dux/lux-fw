require 'test_helper'

describe 'String overloads' do
  describe '#html_escape / #html_unsafe' do
    it 'stores < as &LT; and is idempotent' do
      _('a <b> c'.html_escape).must_equal 'a &LT;b> c'
      _('a <b> c'.html_escape.html_escape).must_equal 'a &LT;b> c'
    end

    it 'migrates the legacy #LT; marker' do
      _('#LT;b>'.html_escape).must_equal '&LT;b>'
    end

    it 'restores markup from both markers' do
      _('&LT;b> #LT;i>'.html_unsafe).must_equal '<b> <i>'
    end

    it 'keeps the full display escape' do
      _(%(<a href="x">).html_escape(true)).must_equal '&lt;a href=&quot;x&quot;&gt;'
    end
  end

  describe '#first' do
    it 'takes a limit like ActiveSupport' do
      _('abc'.first).must_equal 'a'
      _('abc'.first(2)).must_equal 'ab'
    end
  end

  describe '#trim' do
    it 'keeps short strings as is' do
      _('abc'.trim(10)).must_equal 'abc'
    end

    it 'appends a plain-text ellipsis that survives html escaping' do
      _('abcdef'.trim(3)).must_equal 'abc...'
      _(Rack::Utils.escape_html('abcdef'.trim(3))).must_equal 'abc...'
    end
  end
end
