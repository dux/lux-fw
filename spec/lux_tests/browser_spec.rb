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

    it 'core interpolates per-request state' do
      env = Rack::MockRequest.env_for('/')
      Lux::Current.new env
      bundle = Lux::Browser.client_js(:core)
      _(bundle).must_include 'http://test'
      _(bundle).must_match(/Lux\.csrf\s*=\s*"[a-z0-9]+"/)
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

    it 'emits the guard + page reset when the window hash is empty' do
      _(b.window_script).must_equal %[<script id="lux-state">window.app = window.app || {};\nwindow.app.page = {};</script>]
    end

    it 'merges :app into window.app and assigns other keys onto window' do
      b.window[:app] = { cfg: { host: 'http://x' } }
      b.window[:foo] = 1
      tag = b.window_script

      _(tag).must_include 'window.app = window.app || {};'
      _(tag).must_include 'window.app.page = {};'
      _(tag).must_include %[Object.assign(window.app, {"cfg":{"host":"http://x"}});]
      _(tag).must_include %[Object.assign(window, {"foo":1});]

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
      _(html).must_include 'window.app = window.app || {};'
      _(html).must_include '<script id="lux-state">'
    ensure
      Lux.config[:app] = previous
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
