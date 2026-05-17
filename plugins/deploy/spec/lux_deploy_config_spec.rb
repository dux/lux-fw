require 'spec_helper'
require_relative '../lib/lux_deploy'

require 'fileutils'
require 'json'
require 'tmpdir'

describe LuxDeploy::Config do
  def with_app(deploy_json:, extra_files: {})
    Dir.mktmpdir('lux-deploy-spec') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'config/docker'))
      File.write(File.join(dir, 'config/config.yaml'), "secret: test\n")
      File.write(File.join(dir, 'config/deploy.json'), JSON.dump(deploy_json))
      File.write(File.join(dir, 'config/docker/compose.yml'), "services:\n  web:\n    image: ${WEB_IMAGE}\n")
      extra_files.each do |path, body|
        full = File.join(dir, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, body)
      end
      Dir.chdir(dir) { yield dir }
    end
  end

  let(:base) do
    {
      'default' => {
        'server' => 'deploy@srv.example.com',
        'service_user' => 'deployer',
        'env' => { 'RACK_ENV' => 'production' },
        'services' => {
          'web' => {
            'compose_service' => 'web',
            'host_port' => 3100,
            'domains' => ['example.com']
          }
        }
      }
    }
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

  describe '.resolve' do
    it 'resolves placeholders and symbolizes keys' do
      with_app(deploy_json: base) do
        cfg = described_class.resolve('default', app: 'my-app', image_tag: 'abc123')
        expect(cfg[:app]).to eq('my-app')
        expect(cfg[:image_tag]).to eq('abc123')
        expect(cfg[:images][:web]).to eq('my-app-web:abc123')
        expect(cfg[:path]).to eq('/home/deployer/lux-apps/my-app')
        expect(cfg[:compose_project]).to eq('lux-my-app')
      end
    end

    it 'derives root from service_user' do
      with_app(deploy_json: base) do
        cfg = described_class.resolve('default', app: 'my-app')
        expect(cfg[:root]).to eq('/home/deployer/lux-apps')
      end
    end

    it 'auto-detects compose.<profile>.yml when present' do
      data = Marshal.load(Marshal.dump(base))
      data['staging'] = { 'services' => data['default']['services'] }
      extra = { 'config/docker/compose.staging.yml' => "services:\n  web:\n    image: ${WEB_IMAGE}\n" }
      with_app(deploy_json: data, extra_files: extra) do
        cfg = described_class.resolve('staging', app: 'my-app')
        expect(cfg[:compose]).to eq(['config/docker/compose.yml', 'config/docker/compose.staging.yml'])
      end
    end

    it 'rejects locked keys in deploy.json' do
      data = Marshal.load(Marshal.dump(base))
      data['default']['root'] = '/somewhere/else'
      with_app(deploy_json: data) do
        expect { described_class.resolve('default', app: 'my-app') }
          .to raise_error(LuxDeploy::Error, /`root` is not configurable/)
      end
    end

    it 'expands {{host}} to the docker bridge gateway in env values' do
      data = Marshal.load(Marshal.dump(base))
      data['default']['env'] = data['default']['env'].merge(
        'DB_URL' => 'postgresql://app@{{host}}/db'
      )
      with_app(deploy_json: data) do
        cfg = described_class.resolve('default', app: 'my-app')
        expect(cfg[:env][:DB_URL]).to eq('postgresql://app@172.17.0.1/db')
      end
    end

    it 'lets a profile extend another' do
      data = base.merge(
        'staging' => {
          'services' => {
            'web' => {
              'host_port' => 3500,
              'domains' => ['staging.example.com']
            }
          }
        },
        'pr' => {
          'extends' => 'staging',
          'services' => {
            'web' => {
              'host_port' => 3501,
              'domains' => ['{{app}}.staging.example.com']
            }
          }
        }
      )
      with_app(deploy_json: data) do
        cfg = described_class.resolve('pr', app: 'pr-123')
        expect(cfg[:services][:web][:domains]).to eq(['pr-123.staging.example.com'])
        expect(cfg[:services][:web][:host_port]).to eq(3501)
      end
    end

    it 'detects extends cycles' do
      data = base.merge(
        'a' => { 'extends' => 'b' },
        'b' => { 'extends' => 'a' }
      )
      with_app(deploy_json: data) do
        expect { described_class.resolve('a', app: 'cycle') }
          .to raise_error(LuxDeploy::Error, /extends cycle/)
      end
    end

    it 'rejects duplicate domains across services' do
      data = Marshal.load(Marshal.dump(base))
      data['default']['services']['socket'] = {
        'compose_service' => 'socket',
        'host_port' => 3101,
        'domains' => ['example.com']
      }
      with_app(deploy_json: data) do
        expect { described_class.resolve('default', app: 'my-app') }
          .to raise_error(LuxDeploy::Error, /duplicate domain/)
      end
    end

    it 'rejects duplicate host ports across services' do
      data = Marshal.load(Marshal.dump(base))
      data['default']['services']['socket'] = {
        'compose_service' => 'socket',
        'host_port' => 3100,
        'domains' => ['socket.example.com']
      }
      with_app(deploy_json: data) do
        expect { described_class.resolve('default', app: 'my-app') }
          .to raise_error(LuxDeploy::Error, /duplicate host_port/)
      end
    end

    it 'allows host_port null with port_range' do
      data = Marshal.load(Marshal.dump(base))
      data['default']['services']['web']['host_port'] = nil
      data['default']['services']['web']['port_range'] = [3500, 3899]
      with_app(deploy_json: data) do
        cfg = described_class.resolve('default', app: 'my-app')
        expect(cfg[:services][:web][:host_port]).to be_nil
        expect(cfg[:services][:web][:port_range]).to eq([3500, 3899])
      end
    end

    it 'rejects services without domains' do
      data = Marshal.load(Marshal.dump(base))
      data['default']['services']['web']['domains'] = []
      with_app(deploy_json: data) do
        expect { described_class.resolve('default', app: 'my-app') }
          .to raise_error(LuxDeploy::Error, /missing domains/)
      end
    end

    it 'rejects missing compose file' do
      with_app(deploy_json: base) do |dir|
        File.delete(File.join(dir, 'config/docker/compose.yml'))
        expect { described_class.resolve('default', app: 'my-app') }
          .to raise_error(LuxDeploy::Error, /compose file missing/)
      end
    end

    it 'rejects wildcard domain without a tls block' do
      data = Marshal.load(Marshal.dump(base))
      data['default']['services']['web']['domains'] = ['*.example.com']
      with_app(deploy_json: data) do
        expect { described_class.resolve('default', app: 'my-app') }
          .to raise_error(LuxDeploy::Error, /wildcard domain requires tls/)
      end
    end

    it 'accepts a wildcard domain when tls is configured' do
      data = Marshal.load(Marshal.dump(base))
      data['default']['services']['web']['domains'] = ['*.example.com']
      data['default']['tls'] = { 'dns_provider' => 'cloudflare', 'api_token_env' => 'CF_TOKEN' }
      with_app(deploy_json: data) do
        ENV['CF_TOKEN'] = 'tok-xyz'
        cfg = described_class.resolve('default', app: 'my-app')
        expect(cfg[:services][:web][:domains]).to eq(['*.example.com'])
        expect(cfg[:tls][:dns_provider]).to eq('cloudflare')
        expect(cfg[:tls][:api_token_env]).to eq('CF_TOKEN')
      ensure
        ENV.delete('CF_TOKEN')
      end
    end

    it 'rejects an unsupported tls.dns_provider' do
      data = Marshal.load(Marshal.dump(base))
      data['default']['services']['web']['domains'] = ['*.example.com']
      data['default']['tls'] = { 'dns_provider' => 'route53', 'api_token_env' => 'AWS_TOKEN' }
      with_app(deploy_json: data) do
        ENV['AWS_TOKEN'] = 'tok'
        expect { described_class.resolve('default', app: 'my-app') }
          .to raise_error(LuxDeploy::Error, /unsupported tls.dns_provider/)
      ensure
        ENV.delete('AWS_TOKEN')
      end
    end

    it 'rejects when the tls token env var is not set locally' do
      data = Marshal.load(Marshal.dump(base))
      data['default']['services']['web']['domains'] = ['*.example.com']
      data['default']['tls'] = { 'dns_provider' => 'cloudflare', 'api_token_env' => 'NOT_SET_TOKEN' }
      with_app(deploy_json: data) do
        ENV.delete('NOT_SET_TOKEN')
        expect { described_class.resolve('default', app: 'my-app') }
          .to raise_error(LuxDeploy::Error, /tls.api_token_env not set/)
      end
    end

    it 'rejects service keys containing hyphens' do
      data = Marshal.load(Marshal.dump(base))
      data['default']['services']['web-api'] = data['default']['services'].delete('web')
      data['default']['services']['web-api']['host_port'] = 3200
      with_app(deploy_json: data) do
        expect { described_class.resolve('default', app: 'my-app') }
          .to raise_error(LuxDeploy::Error, /invalid service_name/)
      end
    end
  end

  describe 'IMAGE_RE' do
    it 'accepts registry refs with a non-default port' do
      expect('registry.example.com:5000/myapp:tag').to match(described_class::IMAGE_RE)
      expect('localhost:5000/foo/bar:v1.2.3').to match(described_class::IMAGE_RE)
    end

    it 'still accepts plain image refs' do
      expect('myapp-web:latest').to match(described_class::IMAGE_RE)
      expect('myapp/web:abc123').to match(described_class::IMAGE_RE)
    end
  end
end

describe LuxDeploy::Caddy do
  it 'renders one site block per domain group with the right port' do
    ctx = double('ctx',
      config: {
        services: {
          web: { host_port: 3100, domains: ['example.com', 'www.example.com'] },
          socket: { host_port: 3101, domains: ['socket.example.com'] }
        }
      }
    )
    out = described_class.render(ctx)
    expect(out).to include('example.com, www.example.com {')
    expect(out).to include('reverse_proxy 127.0.0.1:3100')
    expect(out).to include('socket.example.com {')
    expect(out).to include('reverse_proxy 127.0.0.1:3101')
  end

  it 'adds scanner block patterns for the web service' do
    ctx = double('ctx',
      config: {
        services: {
          web: { host_port: 3100, domains: ['example.com'] }
        }
      }
    )
    expect(described_class.render(ctx)).to include('@blocked')
  end

  it 'emits a tls{ dns ...} block for wildcard domains when tls is configured' do
    ctx = double('ctx',
      config: {
        tls: { dns_provider: 'cloudflare', api_token_env: 'CF_TOKEN' },
        services: {
          web: { host_port: 3100, domains: ['*.example.com'] }
        }
      }
    )
    out = described_class.render(ctx)
    expect(out).to include('*.example.com {')
    expect(out).to include('tls {')
    expect(out).to include('dns cloudflare {env.CF_TOKEN}')
  end

  it 'omits the tls block for services that only serve apex/subdomains' do
    ctx = double('ctx',
      config: {
        tls: { dns_provider: 'cloudflare', api_token_env: 'CF_TOKEN' },
        services: {
          web: { host_port: 3100, domains: ['example.com'] }
        }
      }
    )
    expect(described_class.render(ctx)).not_to include('tls {')
  end
end

describe LuxDeploy::Compose do
  it 'argv prepends --project-name, --env-file, -f for each compose file' do
    out = described_class.argv(
      project: 'lux-myapp',
      env_file: '/srv/lux-apps/myapp/config/docker/deploy.env',
      compose_files: ['/srv/lux-apps/myapp/config/docker/compose.yml']
    )
    expect(out).to include('docker', 'compose', '--project-name', 'lux-myapp', '--env-file', '/srv/lux-apps/myapp/config/docker/deploy.env', '-f', '/srv/lux-apps/myapp/config/docker/compose.yml')
  end
end

describe LuxDeploy::Image do
  it 'archive_path lives under tmp/deploy/<app>/images.tar.gz' do
    cfg = { app_root: '/x', app: 'myapp' }
    expect(described_class.archive_path(cfg)).to eq('/x/tmp/deploy/myapp/images.tar.gz')
  end
end

describe LuxDeploy::Manifest do
  describe '.env_schema' do
    it 'labels values as required/optional/generated/literal' do
      out = described_class.env_schema(
        SECRET_KEY_BASE: true,
        DB_URL: 'postgres:///x',
        OPTIONAL_FLAG: false,
        POSTGRES_PASSWORD: LuxDeploy::Config::SECRET_GEN_TOKEN
      )
      expect(out).to eq(
        'SECRET_KEY_BASE' => 'required',
        'DB_URL' => 'literal',
        'OPTIONAL_FLAG' => 'optional',
        'POSTGRES_PASSWORD' => 'generated'
      )
    end

    it 'never returns resolved secret values' do
      out = described_class.env_schema(SECRET: 'shhh')
      expect(out.values).to eq(['literal'])
      expect(out.to_s).not_to include('shhh')
    end
  end
end

describe LuxDeploy::Commands do
  describe '.local_test_env_file' do
    it 'expands {{env.KEY}} references in runtime.env' do
      Dir.mktmpdir('lux-deploy-runtime') do |dir|
        config = {
          app_root: dir,
          app: 'myapp',
          quiet: true,
          compose_project: 'lux-myapp',
          images: { web: 'myapp-web:latest' },
          services: { web: { host_port: 3100 } },
          env: {
            'POSTGRES_PASSWORD' => LuxDeploy::Config::SECRET_GEN_TOKEN,
            'DB_URL' => 'postgres://app:{{env.POSTGRES_PASSWORD}}@db:5432/app'
          }
        }
        described_class.local_test_env_file(config)
        runtime = File.read(File.join(LuxDeploy::Image.archive_dir(config), 'runtime.env'))
        pw = runtime[/^POSTGRES_PASSWORD=(.+)$/, 1]
        expect(pw).to match(/\A[a-f0-9]{32}\z/)
        expect(runtime).to include("DB_URL=postgres://app:#{pw}@db:5432/app")
        expect(runtime).not_to include('{{env.')
      end
    end
  end
end

describe LuxDeploy::EnvFile do
  describe '.resolve' do
    it 'reuses existing $generate value when present' do
      env = { 'POSTGRES_PASSWORD' => LuxDeploy::Config::SECRET_GEN_TOKEN }
      existing = { 'POSTGRES_PASSWORD' => 'old-secret' }
      out = described_class.resolve(env, existing, nil)
      expect(out['POSTGRES_PASSWORD']).to eq('old-secret')
    end

    it 'generates a new value for $generate when missing' do
      env = { 'POSTGRES_PASSWORD' => LuxDeploy::Config::SECRET_GEN_TOKEN }
      out = described_class.resolve(env, {}, nil)
      expect(out['POSTGRES_PASSWORD']).to match(/\A[a-f0-9]{64}\z/)
    end

    it 'raises when a required key is not in ENV' do
      env = { 'MUST_HAVE' => true }
      expect { described_class.resolve(env, {}, nil) }
        .to raise_error(LuxDeploy::Error, /required env var not set/)
    end
  end
end
