require 'spec_helper'
require 'fileutils'

describe Lux::Plugin do
  def with_config_snapshot
    snapshot = Lux.config.dup
    yield
  ensure
    Lux.config.clear
    snapshot.each { |key, value| Lux.config[key] = value }
  end

  def tmp_plugin(name)
    root = File.expand_path("../../tmp/#{name}", __dir__)
    FileUtils.rm_rf(root)
    FileUtils.mkdir_p("#{root}/load")
    yield Pathname.new(root)
  ensure
    FileUtils.rm_rf(root) if root
  end

  it 'loads runtime files without evaluating plugin Hammerfiles' do
    tmp_plugin('plugin-loader-spec') do |root|
      plugin_name = root.basename.to_s
      Lux::Plugin.plugins.delete(plugin_name)

      File.write(root.join('load/runtime.rb'), "PluginLoaderSpecLoaded ||= true\n")
      File.write(root.join('Hammerfile'), "raise 'Hammerfile should not load via Lux.plugin'\n")

      plugin = Lux::Plugin.load(root)

      expect(plugin.name).to eq(plugin_name)
      expect(defined?(PluginLoaderSpecLoaded)).to eq('constant')
    ensure
      Lux::Plugin.plugins.delete(plugin_name) if plugin_name
      Object.send(:remove_const, :PluginLoaderSpecLoaded) if defined?(PluginLoaderSpecLoaded)
    end
  end

  it 'merges config.yaml into Lux.config before loading runtime files' do
    with_config_snapshot do
      tmp_plugin('plugin-config-spec') do |root|
        plugin_name = root.basename.to_s
        Lux::Plugin.plugins.delete(plugin_name)

        Lux.config[:plugins] = ['host_plugin']
        Lux.config[:plugin_config_spec] = { 'existing' => 'host' }

        File.write root.join('config.yaml'), <<~YAML
          plugin_config_spec:
            from_plugin: true
          plugins:
            - plugin_dependency
        YAML
        File.write root.join('load/runtime.rb'), <<~RUBY
          PluginConfigSpecRuntimeValue = Lux.config[:plugin_config_spec][:from_plugin]
        RUBY

        Lux::Plugin.load(root)

        expect(Lux.config[:plugin_config_spec][:existing]).to eq('host')
        expect(Lux.config[:plugin_config_spec][:from_plugin]).to eq(true)
        expect(Lux.config[:plugins]).to eq(['host_plugin', 'plugin_dependency'])
        expect(PluginConfigSpecRuntimeValue).to eq(true)
      ensure
        Lux::Plugin.plugins.delete(plugin_name) if plugin_name
        Object.send(:remove_const, :PluginConfigSpecRuntimeValue) if defined?(PluginConfigSpecRuntimeValue)
      end
    end
  end

  it 'appends scalar plugin config to existing plugin config' do
    with_config_snapshot do
      tmp_plugin('plugin-config-scalar-spec') do |root|
        plugin_name = root.basename.to_s
        Lux::Plugin.plugins.delete(plugin_name)

        Lux.config[:plugins] = :host_plugin

        File.write root.join('config.yaml'), <<~YAML
          plugins: plugin_dependency
        YAML

        Lux::Plugin.load(root)

        expect(Lux.config[:plugins]).to eq(['host_plugin', 'plugin_dependency'])
      ensure
        Lux::Plugin.plugins.delete(plugin_name) if plugin_name
      end
    end
  end

  it 'loads a config-only plugin' do
    with_config_snapshot do
      root = Pathname.new(File.expand_path("../../tmp/plugin-config-only-spec", __dir__))
      FileUtils.rm_rf(root)
      FileUtils.mkdir_p(root)
      plugin_name = root.basename.to_s
      Lux::Plugin.plugins.delete(plugin_name)

      File.write root.join('config.yaml'), <<~YAML
        config_only_plugin:
          enabled: true
      YAML

      Lux::Plugin.load(root)

      expect(Lux.config[:config_only_plugin][:enabled]).to eq(true)
    ensure
      Lux::Plugin.plugins.delete(plugin_name) if plugin_name
      FileUtils.rm_rf(root) if root
    end
  end

  it 'merges default-shaped config and top-level plugin dependencies' do
    with_config_snapshot do
      tmp_plugin('plugin-config-default-spec') do |root|
        plugin_name = root.basename.to_s
        Lux::Plugin.plugins.delete(plugin_name)

        Lux.config[:plugins] = ['host_plugin']

        File.write root.join('config.yaml'), <<~YAML
          default:
            plugin_defaults:
              enabled: true
          production:
            plugin_defaults:
              cdn_root: https://cdn.example.test
          plugins:
            - plugin_dependency
        YAML
        File.write(root.join('load/runtime.rb'), '')

        Lux::Plugin.load(root)

        expect(Lux.config[:plugin_defaults][:enabled]).to eq(true)
        expect(Lux.config[:production][:plugin_defaults][:cdn_root]).to eq('https://cdn.example.test')
        expect(Lux.config[:plugins]).to eq(['host_plugin', 'plugin_dependency'])
      ensure
        Lux::Plugin.plugins.delete(plugin_name) if plugin_name
      end
    end
  end

  it 'normalizes configured plugin names' do
    names = Lux::Plugin.normalize_names(nil, false, 'db', [:html, nil, false])

    expect(names).to eq(['db', 'html'])
  end
end
