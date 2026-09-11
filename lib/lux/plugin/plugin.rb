# Plugin layout (canonical):
#   plugins/<name>/
#     config.yaml   # OPTIONAL. Config defaults + `plugins:` dependencies.
#     loader.rb     # OPTIONAL. Boot logic, required before load/.
#     load/         # OPTIONAL. All *.rb auto-required after loader.rb.
#     Hammerfile    # OPTIONAL. Single-file CLI tasks.
#     hammer/       # OPTIONAL. *_hammer.rb CLI tasks.
#     mount/        # OPTIONAL. Mirrors app root. Registered as a Lux::Root
#                   # overlay so its files resolve in place.
#
# Any combination is valid; a plugin with only mount/ (or even just a
# README) is registered and silently does nothing on Lux.plugin :name.

require 'yaml'
require 'deep_merge'
require_relative '../root'

module Lux
  module Plugin
    extend self

    PLUGIN ||= {}

    # Names mid-activation, so a dependency cycle (A -> B -> A) stops instead
    # of recursing forever. A name is dropped once its plugin finishes.
    LOADING ||= {}

    # Low-level: activate a plugin folder. Dependencies are not chased here;
    # use `load_named` (or `Lux.plugin :name`) for that.
    def load plugin_name
      activate Pathname.new(plugin_name)
    end

    # Name-level: find the plugin, load its `plugins:` dependencies first, then
    # activate it. Dependencies load first so their files and constants already
    # exist when the dependent's loader.rb and load/ sweep run, and so their
    # config is the base the dependent's own config overrides.
    def load_named name
      name = name.to_s
      return PLUGIN[name] if PLUGIN.key?(name)
      return nil if LOADING[name]

      root = find(name)
      if root.nil?
        Lux.shell.die [
          "Lux plugin '#{name}' not found",
          "searched: #{search_paths(name).map(&:to_s).join(', ')}"
        ]
      end

      LOADING[name] = true
      begin
        config = read_config(root)
        config_plugins(config).each { |dep| load_named(dep) }
        activate root, config
      ensure
        LOADING.delete(name)
      end
    end

    # Resolve a plugin name to its folder, app root before framework root. An
    # absolute path that points at a directory is used as-is.
    def find name
      path = Pathname.new(name.to_s)
      return path if path.absolute? && path.directory?

      search_paths(name).find(&:exist?)
    end

    def search_paths name
      [Lux.root, Lux.fw_root].map { Pathname.new(_1).join('plugins', name.to_s) }
    end

    # Transitive plugin closure for a set of names, without loading anything.
    # Reads each plugin's config.yaml `plugins:` list. The CLI uses this so a
    # dependency's Hammerfile/hammer tasks are discovered even when the app
    # only lists the dependent.
    def dependency_names names
      result = []
      seen   = {}
      queue  = normalize_names(names).dup

      until queue.empty?
        name = queue.shift
        next if seen[name]
        seen[name] = true

        root = find(name)
        next unless root

        result << name
        config_plugins(read_config(root)).each { |dep| queue << dep unless seen[dep] }
      end

      result
    end

    def normalize_names *values
      values = values.first if values.length == 1

      Array(values).flatten.compact
        .reject { |it| it == false || it.to_s.empty? }
        .map(&:to_s)
        .uniq
    end

    def get name
      PLUGIN[name.to_s] || die('Plugin "%s" not loaded' % name)
    end

    def loaded
      PLUGIN.values
    end

    def loaded? name
      PLUGIN.key?(name.to_s)
    end

    def keys
      PLUGIN.keys
    end

    def plugins
      PLUGIN.dup
    end

    # Forget a loaded plugin (or all of them when name is nil). Boot never
    # unloads; specs use this to load a throwaway plugin and stay isolated.
    def unload name = nil
      return PLUGIN.clear if name.nil?

      PLUGIN.delete(name.to_s)
    end

    # get all plugin folders
    def folders
      PLUGIN.values.map { |it| it.folder }
    end

    private

    def activate root, config = nil
      root = Pathname.new(root)
      name = root.basename.to_s
      die(%{Plugin "#{name}" not found in "#{root}"}) unless root.directory?

      if existing = PLUGIN[name]
        return existing if existing.folder == root.to_s
        Lux.shell.die(%{Plugin "#{name}" already loaded from #{existing.folder}; cannot also load #{root}})
      end

      config ||= read_config(root)

      mount_root = root.join('mount')
      Lux::Root.add(mount_root) if mount_root.directory?

      merge_config(config) if config

      loader   = root.join('loader.rb')
      load_dir = root.join('load')
      require loader.to_s           if loader.exist?
      Dir.require_all load_dir.to_s if load_dir.directory?

      PLUGIN[name] = { folder: root.to_s, name: name }.to_lux_hash
    end

    def config_plugins config
      return [] unless config

      plugins = config['plugins']
      plugins = config[:plugins] if plugins.nil?
      normalize_names(plugins)
    end

    def read_config root
      source = root.join('config.yaml')
      return nil unless source.exist?

      data = YAML.safe_load(source.read, aliases: true) || {}
      die(%{Plugin config "#{source}" must be a hash}) unless data.is_a?(::Hash)

      config_for_env data
    end

    def config_for_env data
      base_key = data.key?('default') ? 'default' : ('base' if data.key?('base'))
      base = data[base_key]
      return data unless base

      base = base.dup
      base.deep_merge!(data[Lux.env.to_s] || {})
      base['production'] = data['production'] if data.key?('production')
      base['plugins'] = normalize_names(base['plugins'], data['plugins']) if data.key?('plugins')
      base['plugins'] = normalize_names(base['plugins'], data[:plugins]) if data.key?(:plugins)
      base
    end

    def merge_config data
      has_plugins = data.key?('plugins') || data.key?(:plugins)
      plugin_names = data.delete('plugins')
      plugin_names = data.delete(:plugins) if plugin_names.nil? && data.key?(:plugins)

      merge_hash! Lux.config, data

      if has_plugins
        Lux.config[:plugins] = normalize_names(Lux.config[:plugins], plugin_names)
      end
    end

    def merge_hash! target, source
      source.each do |key, value|
        if value.is_a?(::Hash) && target[key].is_a?(::Hash)
          merge_hash! target[key], value
        else
          target[key] = value
        end
      end
    end
  end
end
