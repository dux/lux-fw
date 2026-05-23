# Plugin layout (canonical):
#   plugins/<name>/
#     config.yaml   # OPTIONAL. Config defaults, merged first.
#     loader.rb     # OPTIONAL. Boot logic, required before load/.
#     load/         # OPTIONAL. All *.rb auto-required after loader.rb.
#     Hammerfile    # OPTIONAL. Single-file CLI tasks.
#     hammer/       # OPTIONAL. *_hammer.rb CLI tasks.
#     mount/        # OPTIONAL. Mirrors app root. `lux mount` symlinks
#                   # every leaf file into the app at the matching path.
#
# Any combination is valid; a plugin with only mount/ (or even just a
# README) is registered and silently does nothing on Lux.plugin :name.

require 'yaml'
require 'deep_merge'

module Lux
  module Plugin
    extend self

    PLUGIN ||= {}

    # Subsystems append their own instance-method mixin here, and every
    # descriptor returned by Lux.plugin(:name) gets `extend`ed with each
    # registered mixin during `load`. Convention for a subsystem file:
    #
    #   require_relative './plugin'   # ensure this constant exists
    #
    #   module Lux::Plugin::Foo
    #     module Descriptor
    #       def foo!; ...; end
    #     end
    #   end
    #
    #   Lux::Plugin::DESCRIPTOR_MIXINS << Lux::Plugin::Foo::Descriptor \
    #     unless Lux::Plugin::DESCRIPTOR_MIXINS.include?(Lux::Plugin::Foo::Descriptor)
    #
    # Mount uses this for `.mounts` / `.mount!` / `.unmount!`.
    DESCRIPTOR_MIXINS ||= []

    # Lux.plugin :foo
    # Lux.plugin 'foo/bar'
    # Lux.plugin.folders
    # Lux.plugin(:api).folder
    def load plugin_name
      plugin_name = Pathname.new(plugin_name) unless plugin_name.is_a?(Pathname)

      opts = { folder: plugin_name.to_s, name: plugin_name.basename.to_s }.to_lux_hash

      return PLUGIN[opts.name] if PLUGIN[opts.name]

      root = Pathname.new(opts.folder)

      die(%{Plugin "#{opts.name}" not found in "#{root}"}) unless root.directory?

      loader   = root.join('loader.rb')
      load_dir = root.join('load')

      DESCRIPTOR_MIXINS.each { |m| opts.extend(m) }
      PLUGIN[opts.name] ||= opts

      # Config is data, loaded before boot code so loader.rb can read defaults.
      load_config root
      require loader.to_s            if loader.exist?
      Dir.require_all load_dir.to_s  if load_dir.directory?

      PLUGIN[opts.name]
    end

    def normalize_names *values
      values = values.first if values.length == 1

      Array(values).flatten.compact
        .reject { |it| it == false || it.to_s.empty? }
        .map(&:to_s)
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
      PLUGIN
    end

    # get all folders in a namespace
    def folders namespace=:main
      PLUGIN.values.map { |it| it.folder }
    end

    private

    def load_config root
      source = root.join('config.yaml')
      return unless source.exist?

      data = YAML.safe_load(source.read, aliases: true) || {}
      die(%{Plugin config "#{source}" must be a hash}) unless data.is_a?(::Hash)

      merge_config config_for_env(data)
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
