require 'test_helper'

# Slice 1 of the string escaping lifecycle migration
# (doc/string-escaping-lifecycle.plan.md): store-raw / escape-on-output.
# HTML text output escapes only `<`; `.unsafe` opts a value out of escaping while
# keeping <script>/<style> neutralized unless explicitly allowed.
describe 'String#unsafe / Lux::Utils::SafeString / haml escape' do
  # render a haml source string with escaping ON, mirroring the target adapter
  # config (escape_html: true, use_html_safe: true). The global default stays
  # escape_html: false until the migration's final flip, so we set it per call.
  def render src, **locals
    Tilt['haml'].new({ escape_html: true, use_html_safe: true }) { src }
      .render(Object.new, locals).strip
  end

  describe 'Lux::Utils::SafeString' do
    it 'is a String subclass that answers html_safe?' do
      s = Lux::Utils::SafeString.new('x')
      _(s).must_be_kind_of String
      _(s.html_safe?).must_equal true
    end

    # regression guard for the escape_html_safe `html = html.to_s` gotcha:
    # a plain String subclass would lose html_safe? after to_s.
    it 'keeps html_safe? through to_s (does not degrade to plain String)' do
      s = Lux::Utils::SafeString.new('x')
      _(s.to_s.equal?(s)).must_equal true
      _(s.to_s.html_safe?).must_equal true
    end
  end

  describe 'String#unsafe' do
    it 'returns a SafeString' do
      _('x'.unsafe).must_be_kind_of Lux::Utils::SafeString
      _('x'.unsafe.html_safe?).must_equal true
    end

    it 'leaves ordinary tags raw' do
      _('<b>x</b>'.unsafe.to_s).must_equal '<b>x</b>'
    end

    it 'neutralizes <script> and <style> by default' do
      _('<script>a</script>'.unsafe.to_s).must_equal '&lt;script>a&lt;/script>'
      _('<style>a</style>'.unsafe.to_s).must_equal '&lt;style>a&lt;/style>'
    end

    it 'neutralizes script/style case-insensitively' do
      _('<SCRIPT>a</SCRIPT>'.unsafe.to_s).must_equal '&lt;SCRIPT>a&lt;/SCRIPT>'
    end

    it 'allows <script> with script: true' do
      _('<script>a</script>'.unsafe(script: true).to_s).must_equal '<script>a</script>'
    end

    it 'allows <style> with style: true' do
      _('<style>a</style>'.unsafe(style: true).to_s).must_equal '<style>a</style>'
    end

    it 'allows both with unsafe(true)' do
      raw = '<script>a</script><style>b</style>'
      _(raw.unsafe(true).to_s).must_equal raw
    end

    it 'still neutralizes the non-allowed tag when only one is allowed' do
      raw = '<script>a</script><style>b</style>'
      _(raw.unsafe(script: true).to_s).must_equal '<script>a</script>&lt;style>b&lt;/style>'
    end
  end

  describe 'Haml::Util.escape_html_safe (text path, minimal)' do
    it 'escapes only <' do
      _(Haml::Util.escape_html_safe('<b>')).must_equal '&lt;b>'
    end

    it 'leaves &, quotes and > untouched (readability, safe in text nodes)' do
      _(Haml::Util.escape_html_safe(%q{a & b > c "d" 'e'})).must_equal %q{a & b > c "d" 'e'}
    end

    it 'passes html_safe? values through raw' do
      _(Haml::Util.escape_html_safe('<b>'.unsafe(true))).must_equal '<b>'
    end
  end

  describe 'Haml::Util.escape_html (attribute path, unchanged/full)' do
    # we must NOT weaken the attribute escaper - quotes must still be escaped so
    # `%a{title: v}` can never be broken out of.
    it 'still full-entity escapes, including quotes and &' do
      out = Haml::Util.escape_html(%q{<a>&"'})
      _(out).must_include '&lt;'
      _(out).must_include '&amp;'
      _(out).must_include '&quot;'
      _(out).wont_include '"'
    end
  end

  describe 'haml render integration (escape on)' do
    it 'escapes < in a plain interpolated value' do
      _(render('= val', val: '<b>x</b>')).must_equal '&lt;b>x&lt;/b>'
    end

    it 'renders .unsafe values raw' do
      _(render('= val', val: '<b>x</b>'.unsafe)).must_equal '<b>x</b>'
    end

    it 'keeps <script> neutralized even when marked unsafe' do
      _(render('= val', val: '<script>alert(1)</script>'.unsafe))
        .must_equal '&lt;script>alert(1)&lt;/script>'
    end

    it 'emits a live <script> only with unsafe(true)' do
      _(render('= val', val: '<script>alert(1)</script>'.unsafe(true)))
        .must_equal '<script>alert(1)</script>'
    end

    it 'still escapes quotes in attribute values (attribute path intact)' do
      out = render('%a{title: val}', val: %q{" onmouseover="x})
      _(out).must_include '&quot;'
      # the raw breakout sequence must not survive
      _(out).wont_include '" onmouseover="x'
    end
  end
end
