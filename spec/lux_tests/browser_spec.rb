require 'spec_helper'
require 'tmpdir'

describe Lux::Browser do
  # Isolate module state per example. The framework auto-registers :core (and
  # :sse via lib/lux/channel/channel.rb); we save / restore the snapshot.
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

  describe '.register / .modules' do
    it 'registers a module by name + file' do
      Lux::Browser.register :test_mod, file: 'assets/lux/sse.js'
      expect(Lux::Browser.registered?(:test_mod)).to be true
      expect(Lux::Browser.modules).to include(:test_mod)
    end
  end

  describe '.client' do
    it 'returns just core when no other modules requested' do
      bundle = Lux::Browser.client(:core)
      expect(bundle).to include('window.Lux')
      expect(bundle).to include('Lux.fetch')
    end

    it 'prepends core when a module is requested' do
      with_tmp_module :probe, 'window.Lux.probe = "ok";' do
        bundle = Lux::Browser.client(:probe)
        expect(bundle).to include('Lux.fetch')           # core
        expect(bundle).to include('Lux.probe = "ok"')    # the requested module
        expect(bundle.index('Lux.fetch')).to be < bundle.index('Lux.probe = "ok"')
      end
    end

    it 'includes every registered module on no-arg / :all' do
      with_tmp_module :probe, 'window.Lux.probe = "yes";' do
        bundle = Lux::Browser.client
        expect(bundle).to include('Lux.probe = "yes"')
        expect(bundle).to include('Lux.fetch')   # core also present
      end
    end

    it 'raises on unknown module names' do
      expect { Lux::Browser.client(:nope_does_not_exist) }
        .to raise_error(ArgumentError, /unknown module/)
    end

    it 'core interpolates per-request state' do
      # spec_helper sets Lux.config.host = 'http://test'; csrf is lazy-generated.
      env = Rack::MockRequest.env_for('/')
      Lux::Current.new env
      bundle = Lux::Browser.client(:core)
      expect(bundle).to include('http://test')
      expect(bundle).to match(/Lux\.csrf\s*=\s*"[a-z0-9]+"/)
    end
  end
end
