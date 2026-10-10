require 'test_helper'

describe 'String overloads' do
  describe 'output escaping' do
    it 'escapes into a safe string' do
      out = %(<a href="x">).html_escape
      _(out).must_equal '&lt;a href=&quot;x&quot;&gt;'
      assert out.html_safe?
      refute 'plain'.html_safe?
    end

    it 'html_unsafe marks markup and neutralizes script and style by default' do
      out = '<b>x</b><script>1</script><style>a{}</style>'.html_unsafe
      assert out.html_safe?
      _(out).must_equal '<b>x</b>&lt;script>1&lt;/script>&lt;style>a{}&lt;/style>'
      _('<script>1</script>'.html_unsafe(script: true)).must_equal '<script>1</script>'
    end

    it 'escapes plain text appended to a safe string' do
      out = '<b>'.html_unsafe + '<i>'
      assert out.html_safe?
      _(out).must_equal '<b>&lt;i&gt;'
      _(Lux::SafeString.join(['<b>'.html_unsafe, '<i>'], ' ')).must_equal '<b> &lt;i&gt;'
    end

    it 'loses safety on any other transformation' do
      refute '<b>'.html_unsafe.gsub('b', 'i').html_safe?
      refute "#{'<b>'.html_unsafe}".html_safe?
    end

    it 'tag builders escape plain inner text but keep markup' do
      _('<x>'.tag(:b)).must_equal '<b>&lt;x&gt;</b>'
      _('<i>y</i>'.html_unsafe.tag(:b)).must_equal '<b><i>y</i></b>'
      assert 'x'.tag(:b).html_safe?
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
