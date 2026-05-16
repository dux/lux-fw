require 'spec_helper'
require 'fileutils'

describe Lux::Plugin do
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
end
