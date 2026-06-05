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

  describe 'per-request state' do
    def b
      @b ||= Lux::Browser.new
    end

    it 'auto-creates nested nodes on chained access' do
      b.app.config.host = 'http://x'
      b.app.config.locale = 'en'
      _(b.to_h).must_equal('app' => { 'config' => { 'host' => 'http://x', 'locale' => 'en' } })
    end

    it 'supports bracket assignment at any depth' do
      b.app.config[:host] = 'http://x'
      b.app.data[:user]   = { id: 42 }
      _(b.to_h).must_equal('app' => {
        'config' => { 'host' => 'http://x' },
        'data'   => { 'user' => { id: 42 } }   # leaf is untouched, JSON normalises later
      })
    end

    it 'symbol and string keys read the same' do
      b.app.config[:host] = 'http://x'
      _(b.app.config['host']).must_equal 'http://x'
      _(b.app.config[:host]).must_equal 'http://x'
    end

    it 'supports multiple top-level namespaces' do
      b.app.x = 1
      b.api.y = 2
      _(b.to_h).must_equal('app' => { 'x' => 1 }, 'api' => { 'y' => 2 })
    end
  end

  describe '#script_tag' do
    def b
      @b ||= Lux::Browser.new
    end

    it 'emits the default bootstrap and an empty page bucket when no state has been set' do
      tag = b.script_tag
      _(tag).must_equal %[<script id="lux-state">window.app ||= {};\nwindow.app.page = {};</script>]
    end

    it 'level-1 keys get ||= and level-2 keys get full-JSON assignment' do
      b.app.cfg.host   = 'http://x'
      b.app.cfg.locale = 'en'
      tag = b.script_tag

      _(tag).must_include 'window.app ||= {};'
      _(tag).must_include %[window.app.cfg = {"host":"http://x","locale":"en"};]

      assert tag.index('window.app ||=') < tag.index('window.app.cfg =')
    end

    it 'always emits app.page so a navigation clears the prior page payload' do
      b.app.cfg.foo = 1
      tag = b.script_tag
      _(tag).must_include %[window.app.page = {};]
    end

    it 'multiple top-level roots each bootstrap' do
      b.app.cfg.foo = 1
      b.api.url      = '/api'
      tag = b.script_tag

      _(tag).must_include 'window.app ||= {};'
      _(tag).must_include %[window.app.cfg = {"foo":1};]
      _(tag).must_include 'window.api ||= {};'
      _(tag).must_include %[window.api.url = "/api";]
    end

    it 'deep chained creation collapses into level-2 JSON' do
      b.app.current.user.foo.bar = 123
      tag = b.script_tag

      _(tag).must_include 'window.app ||= {};'
      _(tag).must_include %[window.app.current = {"user":{"foo":{"bar":123}}};]
    end

    it 'level-2 primitive is emitted as a plain assignment' do
      b.app.greeting = 'hi'
      tag = b.script_tag
      _(tag).must_include %[window.app.greeting = "hi";]
    end

    it 'hash leaf is JSON-emitted at level-2 (atomic replace, no per-key unroll)' do
      b.app.current.user = { id: 42, name: 'Joe' }
      tag = b.script_tag
      _(tag).must_include %[window.app.current = {"user":{"id":42,"name":"Joe"}};]
    end

    it 'escapes </ inside string values so payload cannot break the tag' do
      b.app.page.danger = "</script><script>x()</script>"
      tag = b.script_tag
      refute_includes tag, '</script><script>'
      _(tag).must_include '<\/script>'
    end

    it 'respects Lux.config.browser_namespace for the bootstrap' do
      previous = Lux.config[:browser_namespace]
      Lux.config[:browser_namespace] = 'fez'
      _(b.script_tag).must_include 'window.fez ||='
    ensure
      Lux.config[:browser_namespace] = previous
    end
  end

  describe 'Lux.current#browser' do
    it 'exposes a per-request instance' do
      env = Rack::MockRequest.env_for('/')
      c = Lux::Current.new env
      _(c.browser).must_be_kind_of Lux::Browser
      c.browser.app.config.x = 1
      _(c.browser.to_h).must_equal('app' => { 'config' => { 'x' => 1 } })
    end

    it 'is memoised per Current' do
      env = Rack::MockRequest.env_for('/')
      c = Lux::Current.new env
      _(c.browser.object_id).must_equal c.browser.object_id
    end
  end
end
