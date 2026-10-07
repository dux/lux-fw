require 'test_helper'
require 'tmpdir'

describe Lux::Browser do
  # Isolate class-level registry per example.
  before do
    @original_modules = Lux::Browser.instance_variable_get(:@modules).dup
    Lux::Browser.instance_variable_set(:@modules, @original_modules.dup)
  end

  after do
    Lux::Browser.instance_variable_set(:@modules, @original_modules)
  end

  def with_tmp_module name, content
    Dir.mktmpdir do |dir|
      path = File.join(dir, "#{name}.js")
      File.write(path, content)
      Lux::Browser.register name, file: path
      yield path
    end
  end

  # ----- class-level: JS module bundler ----------------------------------

  describe '.register / .modules' do
    it 'registers a module by name + file' do
      Lux::Browser.register :test_mod, file: 'assets/lux/sse.js'
      _(Lux::Browser.registered?(:test_mod)).must_equal true
      _(Lux::Browser.modules).must_include :test_mod
    end
  end

  describe '.client_js' do
    it 'returns just core when only core is requested' do
      bundle = Lux::Browser.client_js(:core)
      _(bundle).must_include 'window.Lux'
      _(bundle).must_include 'Lux.fetch'
    end

    it 'prepends core when a module is requested' do
      with_tmp_module :probe, 'window.Lux.probe = "ok";' do
        bundle = Lux::Browser.client_js(:probe)
        _(bundle).must_include 'Lux.fetch'
        _(bundle).must_include 'Lux.probe = "ok"'
        assert bundle.index('Lux.fetch') < bundle.index('Lux.probe = "ok"')
      end
    end

    it 'includes every registered module on no-arg / :all' do
      with_tmp_module :probe, 'window.Lux.probe = "yes";' do
        _(Lux::Browser.client_js).must_include 'Lux.probe = "yes"'
      end
    end

    it 'raises on unknown module names' do
      _{ Lux::Browser.client_js(:nope_does_not_exist) }.must_raise ArgumentError
    end

    it 'core is static (per-request state comes from window_script)' do
      bundle = Lux::Browser.client_js(:core)
      _(bundle).wont_include '<%='
      _(bundle).must_include 'Lux.fetch'
    end
  end


  # ----- instance-level: per-request state ------------------------------

  describe '#window' do
    def b
      @b ||= Lux::Browser.new
    end

    it 'is a plain hash with unrestricted access' do
      _(b.window).must_be_kind_of Hash
      b.window[:app] = { cfg: { host: 'http://x' } }
      b.window[:foo] = 123
      _(b.window).must_equal(app: { cfg: { host: 'http://x' } }, foo: 123)
    end

    it 'pre-seeds the :app bucket so window[:app] is ready to write' do
      _(Lux::Browser.new.window[:app]).must_equal({})
      b.window[:app][:user] = { id: 1 }
      _(b.window).must_equal(app: { user: { id: 1 } })
    end

    it 'is memoised so successive reads see the same hash' do
      b.window[:a] = 1
      _(b.window[:a]).must_equal 1
    end
  end

  describe '#window_script' do
    def b
      @b ||= Lux::Browser.new
    end

    it 'emits Lux bootstrap + app guard when the window hash is empty' do
      env = Rack::MockRequest.env_for('/')
      Lux::Current.new env
      tag = b.window_script
      _(tag).must_include 'window.Lux = window.Lux || {};'
      _(tag).must_include 'Object.assign(window.Lux,'
      _(tag).must_include 'window.app = window.app || {};'
      _(tag).must_include 'window.app.page = {};'
      _(tag).must_include 'csrf'
      _(tag).must_include 'http://test'
    end

    it 'merges :app into window.app and assigns other keys onto window' do
      env = Rack::MockRequest.env_for('/')
      Lux::Current.new env
      b.window[:app] = { cfg: { host: 'http://x' } }
      b.window[:foo] = 1
      tag = b.window_script

      _(tag).must_include 'window.app = window.app || {};'
      _(tag).must_include 'window.app.page = {};'
      _(tag).must_include 'window.Lux = window.Lux || {};'

      # the payload is pretty printed outside production, so match it whitespace-free
      flat = tag.gsub(/\s+/, '')
      _(flat).must_include %[Object.assign(window.app,{"cfg":{"host":"http://x"}});]
      _(flat).must_include %[Object.assign(window,{"foo":1});]

      # page reset precedes the app merge, so app's own page (if any) wins
      assert tag.index('window.app.page = {};') < tag.index('Object.assign(window.app')
    end

    it 'keeps window.app.page = {} when :app is set without a page key' do
      b.window[:app] = { cfg: { host: 'x' } }
      tag = b.window_script
      _(tag).must_include 'window.app.page = {};'
      refute_includes tag, 'Object.assign(window, '   # no non-app keys
    end

    it 'always emits the page reset so a navigation clears the prior page payload' do
      b.window[:foo] = 1
      _(b.window_script).must_include 'window.app.page = {};'
    end

    it 'exports the request render trail as window.app.lux.file_in_use' do
      Lux.current.files_in_use 'app/views/main/index.haml'
      tag = b.window_script    # dev json is pretty printed, so match the parts

      _(tag).must_include '"lux"'
      _(tag).must_include '"file_in_use"'
      _(tag).must_include 'app/views/main/index.haml'
    end

    it 'exports the app root the trail is relative to' do
      Lux.current.files_in_use 'app/views/main/index.haml'
      tag = b.window_script

      _(tag).must_include '"root"'
      _(tag).must_include Lux.root.to_s
    end

    it 'omits the lux bucket in production' do
      Lux.env.define_singleton_method(:prod?) { true }
      Lux.current.files_in_use 'app/views/main/index.haml'

      refute_includes b.window_script, 'file_in_use'
    ensure
      Lux.env.singleton_class.send(:remove_method, :prod?)
    end

    it 'escapes </ inside string values so payload cannot break the tag' do
      b.window[:danger] = "</script><script>x()</script>"
      tag = b.window_script
      refute_includes tag, '</script><script>'
      _(tag).must_include '<\/script>'
    end
  end

  describe '#bundle' do
    it 'delegates to the class-level client_js bundler' do
      _(Lux::Browser.new.bundle(:core)).must_include 'Lux.fetch'
    end
  end

  describe 'header.render bootstrap' do
    it 'emits the window bootstrap via window_script' do
      previous = Lux.config[:app]
      Lux.config[:app] = { name: 'T' }.to_lux_hash
      c = Lux::Current.new Rack::MockRequest.env_for('/')
      html = c.browser.header.render
      _(html).must_include '<script id="lux-state">'
      _(html).must_include 'window.Lux = window.Lux || {};'
      _(html).must_include 'Object.assign(window.Lux,'
      _(html).must_include 'window.app = window.app || {};'
      _(html).must_include 'csrf'
    ensure
      Lux.config[:app] = previous
    end
  end

  describe '#boot_script / #state_script' do
    before { Lux::Current.new Rack::MockRequest.env_for('/') }

    it 'boot carries the Lux surface and app guard, not page state' do
      b = Lux.current.browser
      b.window[:app][:cfg] = { x: 1 }
      tag = b.boot_script
      _(tag).must_include 'Object.assign(window.Lux,'
      _(tag).must_include 'window.app = window.app || {};'
      refute_includes tag, 'window.app.page'
      refute_includes tag, 'lux-state'
    end

    it 'state resets the page, merges app and repeats the Lux cfg' do
      b = Lux.current.browser
      b.window[:app][:cfg] = { x: 1 }
      tag = b.state_script
      _(tag).must_include '<script id="lux-state">'
      _(tag).must_include 'Object.assign(window.Lux,'
      _(tag).must_include 'window.app.page = {};'
      _(tag.gsub(/\s+/, '')).must_include %[Object.assign(window.app,{"cfg":{"x":1}]
    end
  end

  describe '#layout_id / #pjax?' do
    def browser_for headers = {}
      Lux::Current.new(Rack::MockRequest.env_for('/', headers)).browser
    end

    it 'is nil without a layout' do
      b = browser_for
      _(b.layout_id).must_be_nil
      _(b.pjax?).must_equal false
    end

    it 'is stable per layout and differs between layouts' do
      a = browser_for.tap { _1.layout = 'app/views/layouts/main.haml' }
      c = browser_for.tap { _1.layout = 'app/views/layouts/main.haml' }
      d = browser_for.tap { _1.layout = 'app/views/layouts/admin.haml' }
      _(a.layout_id).must_equal c.layout_id
      refute_equal a.layout_id, d.layout_id
    end

    it 'matches the x-pjax-layout request header' do
      id = browser_for.tap { _1.layout = 'main' }.layout_id
      _(browser_for('HTTP_X_PJAX_LAYOUT' => id).tap { _1.layout = 'main' }.pjax?).must_equal true
      _(browser_for('HTTP_X_PJAX_LAYOUT' => 'nope').tap { _1.layout = 'main' }.pjax?).must_equal false
    end
  end

  describe 'render_html' do
    before do
      @previous = Lux.config[:app]
      Lux.config[:app] = { name: 'T' }.to_lux_hash
    end

    after { Lux.config[:app] = @previous }

    def render headers = {}, lang: nil, footer: true, body: true
      c = Lux::Current.new Rack::MockRequest.env_for('/', headers)
      c.browser.layout = 'main'
      c.header.title = 'Page'
      html = c.render_html(lang: lang) do |el|
        el.body(class: 'bg') { '<p>region</p>' } if body
        el.footer(class: 'small') { 'foot' } if footer
        '<link rel="x" href="/x" />'
      end
      [html, c]
    end

    def layout_id
      Lux::Current.new(Rack::MockRequest.env_for('/')).browser.tap { _1.layout = 'main' }.layout_id
    end

    it 'builds the whole document on a full load' do
      html, c = render
      _(html).must_match(/\A<!DOCTYPE html>\n<html lang="en">/)
      _(html).must_include %[<meta name="pjax-layout" content="#{layout_id}" />]
      _(html).must_include '<link rel="x" href="/x" />'
      _(html).must_include '<title>Page | T</title>'
      _(html).must_include '<body class="bg">'
      _(html).must_include '<div class="pjax" id="main"><script id="lux-state">'
      _(html).must_include '<p>region</p></div>'
      _(html).must_include '<footer class="small">foot</footer>'
      _(c.response.headers['x-pjax-layout']).must_equal layout_id
      _(c.response.headers['vary']).must_equal 'x-pjax-layout'

      # boot runs before head extras (bundles), state lives in the region
      assert html.index('Object.assign(window.Lux') < html.index('<link rel="x"')
      assert html.index('<link rel="x"') < html.index('lux-state')
    end

    it 'takes lang from the locale, or an explicit one' do
      Lux::Current.new Rack::MockRequest.env_for('/')
      _(render(lang: 'hr_HR').first).must_include '<html lang="hr-HR">'
    end

    it 'returns only title + region for a pjax request of the same layout' do
      html, = render({ 'HTTP_X_PJAX_LAYOUT' => layout_id })
      _(html).must_match(/\A<title>Page \| T<\/title>\n<div class="pjax" id="main"><script id="lux-state">/)
      refute_includes html, '<head>'
      refute_includes html, 'footer'
      refute_includes html, '<link rel="x"'
    end

    it 'blanks assets on pjax' do
      c = Lux::Current.new Rack::MockRequest.env_for('/', 'HTTP_X_PJAX_LAYOUT' => layout_id)
      c.browser.layout = 'main'
      _(c.browser.html.asset('app.js')).must_equal ''
      _(c.browser.html.assets(:app)).must_equal ''
    end

    it 'renders preconnect links' do
      el = Lux::Current.new(Rack::MockRequest.env_for('/')).browser.html
      _(el.preconnect('https://x.com')).must_equal '<link rel="preconnect" href="https://x.com" />'
      _(el.google_fonts_preconnect).must_include '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="" />'
    end

    it 'el.title sets the header title' do
      c = Lux::Current.new Rack::MockRequest.env_for('/')
      html = c.render_html { |el| el.title 'Preview'; el.body { 'x' }; '' }
      _(html).must_include '<title>Preview | T</title>'
    end

    it 'raises without el.body' do
      _ { render(body: false) }.must_raise ArgumentError
    end
  end

  describe 'Lux.current#browser' do
    it 'is the master per-request object with header + window' do
      env = Rack::MockRequest.env_for('/')
      c = Lux::Current.new env
      _(c.browser).must_be_kind_of Lux::Browser
      _(c.browser.header).must_be_kind_of Lux::Browser::Header
      _(c.browser.window).must_be_kind_of Hash
      c.browser.window[:app] = { x: 1 }
      _(c.browser.window).must_equal(app: { x: 1 })
    end

    it 'memoises, points lux.header at lux.browser.header, and back-refs the browser' do
      env = Rack::MockRequest.env_for('/')
      c = Lux::Current.new env
      _(c.browser.object_id).must_equal c.browser.object_id
      _(c.browser.window.object_id).must_equal c.browser.window.object_id
      _(c.header.object_id).must_equal c.browser.header.object_id
      _(c.browser.header.browser).must_equal c.browser
    end
  end
end
