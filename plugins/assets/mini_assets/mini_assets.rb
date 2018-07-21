# app/assets/main/js.assets
# ---
# add 'js_vendor/*'
# add 'js/*'
# add 'index.coffee'

# render production asset
# ---
# MiniAssets.call('js/main/index.coffee').render

# render single asset
# ---
# asset = MiniAssets::Asset.call(path)
# asset.content_type
# asset.render

require 'json'
require 'pathname'
require 'awesome_print'
require 'open3'
require 'digest'

# calls base classes
class MiniAssets
  attr_reader :files

  def initialize source
    @files   = []
    @fsource = source

    @source = MiniAssets::Opts.app_root.join source

    # fill @files, via dsl or direct
    if source.split('.').last == 'assets'
      # add './js/*'
      eval @source.read
    else
      @source.read.split($/).each do |line|
        test = line.split(/^[\/#]+=\s*req\w*\s+/)
        add test[1] if test[1]
      end

      @files.push source
    end

    # figure out type unless defined
    unless @type
      ext = @files.first.split('.').last
      @type = ['css', 'sass', 'scss'].include?(ext) ? :css : :js
    end
  end

  def type name
    @type = name
  end

  def add files
    if files.starts_with?('plugin:')
      real_path = files.sub(%r{^plugin:([^/]+)}) do
        plugin = Lux::PLUGINS[$1]
        die "Plugin %s not loaded, I have %s" % [$1, Lux::PLUGINS.keys.join(', ')] unless plugin
        plugin + '/assets'
      end

      @files += Dir[real_path]
    else
      files  = files.sub(/^\.\//,'')
      path   = files[0,1] == '/' ? "#{Lux.root}/app/assets#{files}" : @source.dirname.join(files)
      @files += Dir[path].sort.map{ |f| f.split('/app/assets/', 2).last }
    end

    @files
  end

  # render production file
  def render
    # load right base class
    base_class = @type == :css ?
      MiniAssets::Base::StyleSheet
      : MiniAssets::Base::JavaScript

    base_class.new(@fsource, @files).render
  end
end