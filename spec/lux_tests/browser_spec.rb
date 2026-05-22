require 'spec_helper'
require 'tmpdir'

describe Lux::Browser do
  # Isolate class-level registry per example.
  around do |example|
    original = Lux::Browser.instance_variable_get(:@modules).dup
    Lux::Browser.instance_variable_set(:@modules, original.dup)
    example.run
  ensure
    Lux::Browser.instance_variable_set(:@modules, original)
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
      expect(Lux::Browser.registered?(:test_mod)).to be true
      expect(Lux::Browser.modules).to include(:test_mod)
    end
  end

  describe '.client' do
    it 'returns just core when only core is requested' do
      bundle = Lux::Browser.client(:core)
      expect(bundle).to include('window.Lux')
      expect(bundle).to include('Lux.fetch')
    end

    it 'prepends core when a module is requested' do
      with_tmp_module :probe, 'window.Lux.probe = "ok";' do
        bundle = Lux::Browser.client(:probe)
        expect(bundle).to include('Lux.fetch')
        expect(bundle).to include('Lux.probe = "ok"')
        expect(bundle.index('Lux.fetch')).to be < bundle.index('Lux.probe = "ok"')
      end
    end

    it 'includes every registered module on no-arg / :all' do
      with_tmp_module :probe, 'window.Lux.probe = "yes";' do
        expect(Lux::Browser.client).to include('Lux.probe = "yes"')
      end
    end

    it 'raises on unknown module names' do
      expect { Lux::Browser.client(:nope_does_not_exist) }
        .to raise_error(ArgumentError, /unknown module/)
    end

    it 'core interpolates per-request state' do
      env = Rack::MockRequest.env_for('/')
      Lux::Current.new env
      bundle = Lux::Browser.client(:core)
      expect(bundle).to include('http://test')
      expect(bundle).to match(/Lux\.csrf\s*=\s*"[a-z0-9]+"/)
    end
  end

  # ----- instance-level: per-request state ------------------------------

  describe 'per-request state' do
    let(:b) { Lux::Browser.new }

    it 'auto-creates nested nodes on chained access' do
      b.app.config.host = 'http://x'
      b.app.config.locale = 'en'
      expect(b.to_h).to eq('app' => { 'config' => { 'host' => 'http://x', 'locale' => 'en' } })
    end

    it 'supports bracket assignment at any depth' do
      b.app.config[:host] = 'http://x'
      b.app.data[:user]   = { id: 42 }
      expect(b.to_h).to eq('app' => {
        'config' => { 'host' => 'http://x' },
        'data'   => { 'user' => { id: 42 } }   # leaf is untouched, JSON normalises later
      })
    end

    it 'symbol and string keys read the same' do
      b.app.config[:host] = 'http://x'
      expect(b.app.config['host']).to eq('http://x')
      expect(b.app.config[:host]).to eq('http://x')
    end

    it 'supports multiple top-level namespaces' do
      b.app.x = 1
      b.api.y = 2
      expect(b.to_h).to eq('app' => { 'x' => 1 }, 'api' => { 'y' => 2 })
    end
  end

  describe '#script_tag' do
    let(:b) { Lux::Browser.new }

    it 'emits the default bootstrap when no state has been set' do
      tag = b.script_tag
      expect(tag).to eq(%[<script id="lux-state">window.app ||= {};</script>])
    end

    it 'level-1 keys get ||= and level-2 keys get full-JSON assignment' do
      b.app.config.host   = 'http://x'
      b.app.config.locale = 'en'
      tag = b.script_tag

      expect(tag).to include('window.app ||= {};')
      expect(tag).to include(%[window.app.config = {"host":"http://x","locale":"en"};])

      expect(tag.index('window.app ||='))
        .to be < tag.index('window.app.config =')
    end

    it 'multiple top-level roots each bootstrap' do
      b.app.config.foo = 1
      b.api.url        = '/api'
      tag = b.script_tag

      expect(tag).to include('window.app ||= {};')
      expect(tag).to include(%[window.app.config = {"foo":1};])
      expect(tag).to include('window.api ||= {};')
      expect(tag).to include(%[window.api.url = "/api";])
    end

    it 'deep chained creation collapses into level-2 JSON' do
      b.app.data.user.foo.bar = 123
      tag = b.script_tag

      expect(tag).to include('window.app ||= {};')
      expect(tag).to include(%[window.app.data = {"user":{"foo":{"bar":123}}};])
    end

    it 'level-2 primitive is emitted as a plain assignment' do
      b.app.greeting = 'hi'
      tag = b.script_tag
      expect(tag).to include(%[window.app.greeting = "hi";])
    end

    it 'hash leaf is JSON-emitted at level-2 (atomic replace, no per-key unroll)' do
      b.app.data.user = { id: 42, name: 'Joe' }
      tag = b.script_tag
      expect(tag).to include(%[window.app.data = {"user":{"id":42,"name":"Joe"}};])
    end

    it 'escapes </ inside string values so payload cannot break the tag' do
      b.app.data.danger = "</script><script>x()</script>"
      tag = b.script_tag
      expect(tag).not_to include('</script><script>')
      expect(tag).to include('<\/script>')
    end

    it 'respects Lux.config.browser_namespace for the empty bootstrap' do
      previous = Lux.config[:browser_namespace]
      Lux.config[:browser_namespace] = 'fez'
      expect(b.script_tag).to include('window.fez ||=')
    ensure
      Lux.config[:browser_namespace] = previous
    end
  end

  describe 'Lux.current#browser' do
    it 'exposes a per-request instance' do
      env = Rack::MockRequest.env_for('/')
      c = Lux::Current.new env
      expect(c.browser).to be_a(Lux::Browser)
      c.browser.app.config.x = 1
      expect(c.browser.to_h).to eq('app' => { 'config' => { 'x' => 1 } })
    end

    it 'is memoised per Current' do
      env = Rack::MockRequest.env_for('/')
      c = Lux::Current.new env
      expect(c.browser).to equal(c.browser)
    end
  end
end
