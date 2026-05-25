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

  it 'initializes LUX_ENV from RACK_ENV when LUX_ENV is empty' do
    old_lux_env = ENV['LUX_ENV']
    old_rack_env = ENV['RACK_ENV']

    ENV['LUX_ENV'] = ''
    ENV['RACK_ENV'] = 'test'

    _(Lux.init_env).must_equal 'test'
    _(ENV['LUX_ENV']).must_equal 'test'
  ensure
    ENV['LUX_ENV'] = old_lux_env
    ENV['RACK_ENV'] = old_rack_env
  end
end
