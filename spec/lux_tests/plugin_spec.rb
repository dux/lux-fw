require 'test_helper'
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

  # A throwaway plugin in the framework plugins dir, so name resolution
  # (`Lux::Plugin.find`) reaches it. Caller cleans up.
  def framework_plugin(name)
    root = Lux.fw_root.join('plugins', name)
    FileUtils.rm_rf(root)
    FileUtils.mkdir_p(root.join('load'))
    yield root
    root
  end

  it 'loads runtime files without evaluating plugin Hammerfiles' do
    tmp_plugin('plugin-loader-spec') do |root|
      plugin_name = root.basename.to_s
      Lux::Plugin.unload(plugin_name)

      File.write(root.join('load/runtime.rb'), "PluginLoaderSpecLoaded ||= true\n")
      File.write(root.join('Hammerfile'), "raise 'Hammerfile should not load via Lux.plugin'\n")

      plugin = Lux::Plugin.load(root)

      _(plugin.name).must_equal plugin_name
      _(defined?(PluginLoaderSpecLoaded)).must_equal 'constant'
    ensure
      Lux::Plugin.unload(plugin_name) if plugin_name
      Object.send(:remove_const, :PluginLoaderSpecLoaded) if defined?(PluginLoaderSpecLoaded)
    end
  end

  it 'merges config.yaml into Lux.config before loading runtime files' do
    with_config_snapshot do
      tmp_plugin('plugin-config-spec') do |root|
        plugin_name = root.basename.to_s
        Lux::Plugin.unload(plugin_name)

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

        _(Lux.config[:plugin_config_spec][:existing]).must_equal 'host'
        _(Lux.config[:plugin_config_spec][:from_plugin]).must_equal true
        _(Lux.config[:plugins]).must_equal ['host_plugin', 'plugin_dependency']
        _(PluginConfigSpecRuntimeValue).must_equal true
      ensure
        Lux::Plugin.unload(plugin_name) if plugin_name
        Object.send(:remove_const, :PluginConfigSpecRuntimeValue) if defined?(PluginConfigSpecRuntimeValue)
      end
    end
  end

  it 'appends scalar plugin config to existing plugin config' do
    with_config_snapshot do
      tmp_plugin('plugin-config-scalar-spec') do |root|
        plugin_name = root.basename.to_s
        Lux::Plugin.unload(plugin_name)

        Lux.config[:plugins] = :host_plugin

        File.write root.join('config.yaml'), <<~YAML
          plugins: plugin_dependency
        YAML

        Lux::Plugin.load(root)

        _(Lux.config[:plugins]).must_equal ['host_plugin', 'plugin_dependency']
      ensure
        Lux::Plugin.unload(plugin_name) if plugin_name
      end
    end
  end

  it 'loads a config-only plugin' do
    with_config_snapshot do
      root = Pathname.new(File.expand_path("../../tmp/plugin-config-only-spec", __dir__))
      FileUtils.rm_rf(root)
      FileUtils.mkdir_p(root)
      plugin_name = root.basename.to_s
      Lux::Plugin.unload(plugin_name)

      File.write root.join('config.yaml'), <<~YAML
        config_only_plugin:
          enabled: true
      YAML

      Lux::Plugin.load(root)

      _(Lux.config[:config_only_plugin][:enabled]).must_equal true
    ensure
      Lux::Plugin.unload(plugin_name) if plugin_name
      FileUtils.rm_rf(root) if root
    end
  end

  it 'merges default-shaped config and top-level plugin dependencies' do
    with_config_snapshot do
      tmp_plugin('plugin-config-default-spec') do |root|
        plugin_name = root.basename.to_s
        Lux::Plugin.unload(plugin_name)

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

        _(Lux.config[:plugin_defaults][:enabled]).must_equal true
        _(Lux.config[:production][:plugin_defaults][:cdn_root]).must_equal 'https://cdn.example.test'
        _(Lux.config[:plugins]).must_equal ['host_plugin', 'plugin_dependency']
      ensure
        Lux::Plugin.unload(plugin_name) if plugin_name
      end
    end
  end

  it 'normalizes configured plugin names and drops duplicates' do
    names = Lux::Plugin.normalize_names(nil, false, 'db', [:html, nil, false], 'db')

    _(names).must_equal ['db', 'html']
  end

  it 'loads declared dependencies before the dependent' do
    suffix = "#{Process.pid}_#{rand(1_000_000)}"
    dep    = "plugin_spec_dep_#{suffix}"
    host   = "plugin_spec_host_#{suffix}"
    dep_root = host_root = nil

    dep_root = framework_plugin(dep) do |root|
      File.write(root.join('load/dep.rb'), "PluginSpecDepLoaded ||= true\n")
    end
    host_root = framework_plugin(host) do |root|
      File.write(root.join('config.yaml'), "plugins: [#{dep}]\n")
      File.write(root.join('loader.rb'), "raise 'dependency not loaded first' unless defined?(PluginSpecDepLoaded)\n")
    end

    Lux::Plugin.load_named(host)

    assert Lux::Plugin.loaded?(dep)
    assert Lux::Plugin.loaded?(host)
    assert Lux::Plugin.keys.index(dep) < Lux::Plugin.keys.index(host)
  ensure
    Lux::Plugin.unload(dep)
    Lux::Plugin.unload(host)
    Object.send(:remove_const, :PluginSpecDepLoaded) if defined?(PluginSpecDepLoaded)
    FileUtils.rm_rf(dep_root) if dep_root
    FileUtils.rm_rf(host_root) if host_root
  end

  it 'stops a plugin dependency cycle instead of recursing' do
    suffix = "#{Process.pid}_#{rand(1_000_000)}"
    a = "plugin_spec_cycle_a_#{suffix}"
    b = "plugin_spec_cycle_b_#{suffix}"
    a_root = b_root = nil

    a_root = framework_plugin(a) { |root| File.write(root.join('config.yaml'), "plugins: [#{b}]\n") }
    b_root = framework_plugin(b) { |root| File.write(root.join('config.yaml'), "plugins: [#{a}]\n") }

    Lux::Plugin.load_named(a)

    assert Lux::Plugin.loaded?(a)
    assert Lux::Plugin.loaded?(b)
  ensure
    Lux::Plugin.unload(a)
    Lux::Plugin.unload(b)
    FileUtils.rm_rf(a_root) if a_root
    FileUtils.rm_rf(b_root) if b_root
  end

  it 'does not register a plugin whose loader raises' do
    tmp_plugin('plugin-loader-raises-spec') do |root|
      plugin_name = root.basename.to_s
      Lux::Plugin.unload(plugin_name)
      File.write(root.join('loader.rb'), "raise 'boom in loader'\n")

      assert_raises(RuntimeError) { Lux::Plugin.load(root) }
      refute Lux::Plugin.loaded?(plugin_name)
    ensure
      Lux::Plugin.unload(plugin_name) if plugin_name
    end
  end

  it 'refuses a second plugin sharing a name from another folder' do
    a = b = nil
    a = Pathname.new(File.expand_path('../../tmp/collide_a/dup', __dir__))
    b = Pathname.new(File.expand_path('../../tmp/collide_b/dup', __dir__))
    [a, b].each { |root| FileUtils.mkdir_p(root) }

    Lux::Plugin.load(a)
    error = assert_raises(Lux::Shell::Die) { Lux::Plugin.load(b) }

    assert_includes error.message, 'already loaded'
  ensure
    Lux::Plugin.unload('dup')
    FileUtils.rm_rf(a) if a
    FileUtils.rm_rf(b) if b
  end

  it 'expands configured plugin names with their config.yaml dependencies' do
    _(Lux::Plugin.dependency_names(['web_common'])).must_equal ['web_common', 'authcog']
  end
end
