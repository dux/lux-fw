require 'spec_helper'
require_relative '../lib/lux_deploy'

require 'fileutils'
require 'json'
require 'tmpdir'

describe LuxDeploy::Config do
  def with_app(deploy_json:, extra_files: {})
    Dir.mktmpdir('lux-deploy-spec') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'config'))
      File.write(File.join(dir, 'config/config.yaml'), "secret: test\n")
      File.write(File.join(dir, 'config/deploy.json'), JSON.dump(deploy_json))
      extra_files.each { |path, body| File.write(File.join(dir, path), body) }
      Dir.chdir(dir) { yield dir }
    end
  end

  describe '.deep_merge' do
    it 'merges nested hashes' do
      a = { 'a' => 1, 'b' => { 'x' => 1, 'y' => 2 } }
      b = { 'b' => { 'y' => 9, 'z' => 3 }, 'c' => 4 }
      expect(described_class.deep_merge(a, b)).to eq(
        'a' => 1, 'b' => { 'x' => 1, 'y' => 9, 'z' => 3 }, 'c' => 4
      )
    end

    it 'treats nil sides as empty hashes' do
      expect(described_class.deep_merge(nil, { 'a' => 1 })).to eq('a' => 1)
      expect(described_class.deep_merge({ 'a' => 1 }, nil)).to eq('a' => 1)
    end
  end

  describe '.parse_env_opts' do
    it 'parses KEY=VAL pairs and bare KEYs' do
      out = described_class.parse_env_opts('FOO=bar,BAZ')
      expect(out).to eq('FOO' => 'bar', 'BAZ' => true)
    end

    it 'returns {} for nil or empty input' do
      expect(described_class.parse_env_opts(nil)).to eq({})
      expect(described_class.parse_env_opts('')).to eq({})
    end
  end

  describe 'LuxDeploy.hash_port' do
    it 'returns a stable port in 3000..3999 for an app name' do
      port = LuxDeploy.hash_port('myapp')
      expect(port).to be_between(3000, 3999)
      expect(LuxDeploy.hash_port('myapp')).to eq(port)
    end
  end

  describe '.resolve' do
    let(:base) do
      {
        'default' => {
          'host' => 'deploy@srv.example.com',
          'path' => '/var/www/{{app}}',
          'ruby' => '3.4.7',
          'domain' => 'example.com',
          'db' => { 'name' => '{{app_underscored}}', 'user' => 'deploy' },
          'healthcheck' => { 'path' => '/', 'timeout' => 30, 'expect_status' => [200] },
          'env' => { 'RACK_ENV' => 'production' }
        }
      }
    end

    it 'resolves placeholders and symbolizes keys' do
      with_app(deploy_json: base) do
        cfg = described_class.resolve('default', app: 'my-app', src: Dir.pwd)
        expect(cfg[:app]).to eq('my-app')
        expect(cfg[:path]).to eq('/var/www/my-app')
        expect(cfg[:db][:name]).to eq('my_app')
        expect(cfg[:env][:RACK_ENV]).to eq('production')
      end
    end

    it 'lets a profile extend another' do
      data = base.merge(
        'staging' => { 'domain' => 'staging.example.com' },
        'pr' => { 'extends' => 'staging', 'domain' => '{{app}}.staging.example.com' }
      )
      with_app(deploy_json: data) do
        cfg = described_class.resolve('pr', app: 'pr-123', src: Dir.pwd)
        expect(cfg[:domain]).to eq('pr-123.staging.example.com')
        expect(cfg[:ruby]).to eq('3.4.7')
      end
    end

    it 'detects extends cycles' do
      data = base.merge(
        'a' => { 'extends' => 'b' },
        'b' => { 'extends' => 'a' }
      )
      with_app(deploy_json: data) do
        expect { described_class.resolve('a', app: 'cycle', src: Dir.pwd) }
          .to raise_error(LuxDeploy::Error, /extends cycle/)
      end
    end

    it 'rejects Postgres reserved words as db identifiers' do
      data = base.merge(
        'default' => base['default'].merge('db' => { 'name' => 'user', 'user' => 'deploy' })
      )
      with_app(deploy_json: data) do
        expect { described_class.resolve('default', app: 'app', src: Dir.pwd) }
          .to raise_error(LuxDeploy::Error, /invalid db_name/)
      end
    end

    it 'rejects --branch with --src' do
      with_app(deploy_json: base) do
        expect do
          described_class.resolve('default', app: 'myapp', src: Dir.pwd, branch: 'main')
        end.to raise_error(LuxDeploy::Error, /mutually exclusive/)
      end
    end
  end
end
