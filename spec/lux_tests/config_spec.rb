require 'spec_helper'
require 'fileutils'
require 'tmpdir'

describe Lux::Config do
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
      config = described_class.load

      expect(config['host']).to eq('http://test')
      expect(config['production']['host']).to eq('https://example.com')
    end
  end

  it 'raises when config yaml is empty' do
    with_config_file '' do
      expect { described_class.load }.to raise_error(RuntimeError, /Config root must be a Hash/)
    end
  end

  it 'raises when config root is not a hash' do
    with_config_file "- host\n" do
      expect { described_class.load }.to raise_error(RuntimeError, /Config root must be a Hash/)
    end
  end

  it 'raises when default root is missing' do
    with_config_file <<~YAML do
      test:
        host: http://test
    YAML
      expect { described_class.load }.to raise_error(RuntimeError, /Config :default\/:base root not defined/)
    end
  end

  it 'raises when default root is not a hash' do
    with_config_file "default: false\n" do
      expect { described_class.load }.to raise_error(RuntimeError, /Config :default root must be a Hash/)
    end
  end

  it 'raises when current env section is not a hash' do
    with_config_file <<~YAML do
      default:
        host: http://default
      test: false
    YAML
      expect { described_class.load }.to raise_error(RuntimeError, /Config :test section must be a Hash/)
    end
  end

  it 'raises when production section is not a hash' do
    with_config_file <<~YAML do
      default:
        host: http://default
      production: false
    YAML
      expect { described_class.load }.to raise_error(RuntimeError, /Config :production section must be a Hash/)
    end
  end

  it 'initializes LUX_ENV from RACK_ENV when LUX_ENV is empty' do
    old_lux_env = ENV['LUX_ENV']
    old_rack_env = ENV['RACK_ENV']

    ENV['LUX_ENV'] = ''
    ENV['RACK_ENV'] = 'test'

    expect(Lux.init_env).to eq('test')
    expect(ENV['LUX_ENV']).to eq('test')
  ensure
    ENV['LUX_ENV'] = old_lux_env
    ENV['RACK_ENV'] = old_rack_env
  end
end
