require 'test_helper'
require 'fileutils'
require 'tmpdir'

describe Lux::Boot::Config do
  # Lux::Boot::Config.load reports invalid YAML via Lux.shell.die, which calls
  # exit(1). Reopen the shell singleton so die raises a RuntimeError we can
  # assert on, then restore the original after each example.
  before do
    @original_die = Lux::Shell.method(:die)
    Lux::Shell.define_singleton_method(:die) do |text|
      lines = Array(text).map(&:to_s)
      raise RuntimeError, lines.join(' | ')
    end
  end

  after do
    original = @original_die
    Lux::Shell.define_singleton_method(:die) { |text| original.call(text) }
  end

  def with_config_file content
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p File.join(dir, 'config')
      File.write File.join(dir, 'config', 'config.yaml'), content

      Dir.chdir(dir) { yield }
    end
  end

  it 'loads default plus current env and keeps production config' do
    with_config_file <<~YAML do
      default:
        host: http://default
      test:
        host: http://test
      production:
        host: https://example.com
    YAML
      config = Lux::Boot::Config.load

      _(config['host']).must_equal 'http://test'
      _(config['production']['host']).must_equal 'https://example.com'
    end
  end

  it 'raises when config yaml is empty' do
    with_config_file '' do
      err = _{ Lux::Boot::Config.load }.must_raise RuntimeError
      _(err.message).must_match(/Config root must be a Hash|root must be a Hash/)
    end
  end

  it 'raises when config root is not a hash' do
    with_config_file "- host\n" do
      err = _{ Lux::Boot::Config.load }.must_raise RuntimeError
      _(err.message).must_match(/root must be a Hash/)
    end
  end

  it 'raises when default root is missing' do
    with_config_file <<~YAML do
      test:
        host: http://test
    YAML
      err = _{ Lux::Boot::Config.load }.must_raise RuntimeError
      _(err.message).must_match(/:default \/ :base root not defined|:default\/:base root not defined/)
    end
  end

  it 'raises when default root is not a hash' do
    with_config_file "default: false\n" do
      err = _{ Lux::Boot::Config.load }.must_raise RuntimeError
      _(err.message).must_match(/:default root must be a Hash/)
    end
  end

  it 'raises when current env section is not a hash' do
    with_config_file <<~YAML do
      default:
        host: http://default
      test: false
    YAML
      err = _{ Lux::Boot::Config.load }.must_raise RuntimeError
      _(err.message).must_match(/:test section must be a Hash/)
    end
  end

  it 'raises when production section is not a hash' do
    with_config_file <<~YAML do
      default:
        host: http://default
      production: false
    YAML
      err = _{ Lux::Boot::Config.load }.must_raise RuntimeError
      _(err.message).must_match(/:production section must be a Hash/)
    end
  end

  # set_defaults is private (internal to boot!), hence send. It runs after the
  # config.yaml load, so it must not overwrite what
  # the host declared. `=` used to clobber every key here; `||=` would still flip
  # an explicit false back on for a true-default.
  describe '.set_defaults' do
    def with_config keys
      was = keys.keys.each_with_object({}) { |k, h| h[k] = Lux.config.key?(k) ? Lux.config[k] : :_absent }
      keys.each { |k, v| v == :_absent ? Lux.config.delete(k.to_s) : Lux.config[k] = v }
      yield
    ensure
      was.each { |k, v| v == :_absent ? Lux.config.delete(k.to_s) : Lux.config[k] = v }
    end

    it 'does not overwrite a value the host declared' do
      with_config(logger_files_to_keep: 99) do
        Lux::Boot.send(:set_defaults)
        _(Lux.config[:logger_files_to_keep]).must_equal 99
      end
    end

    it 'keeps an explicit false against a true default' do
      with_config(serve_static_files: false) do
        Lux::Boot.send(:set_defaults)
        _(Lux.config[:serve_static_files]).must_equal false
      end
    end

    it 'keeps an explicit true against a false default' do
      with_config(asset_root: true) do
        Lux::Boot.send(:set_defaults)
        _(Lux.config[:asset_root]).must_equal true
      end
    end

    it 'keeps an explicit nil rather than re-defaulting it' do
      with_config(ref_format: nil) do
        Lux::Boot.send(:set_defaults)
        _(Lux.config[:ref_format]).must_be_nil
      end
    end

    it 'fills in a key the host left out' do
      with_config(serve_static_files: :_absent) do
        Lux::Boot.send(:set_defaults)
        _(Lux.config[:serve_static_files]).must_equal true
      end
    end
  end

  it 'defaults LUX_ENV to development when empty and mirrors it into RACK_ENV' do
    old_lux_env = ENV['LUX_ENV']
    old_rack_env = ENV['RACK_ENV']

    ENV['LUX_ENV'] = ''
    ENV.delete('RACK_ENV')

    _(Lux.init_env).must_equal 'development'
    _(ENV['LUX_ENV']).must_equal 'development'
    _(ENV['RACK_ENV']).must_equal 'development'
  ensure
    ENV['LUX_ENV'] = old_lux_env
    ENV['RACK_ENV'] = old_rack_env
  end
end
