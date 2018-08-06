class SimpleAssets::Asset

  def initialize source, opts={}
    unless source.starts_with?('/')
      if source =~ %r{^plugin:}
        source = source.sub(%r{^plugin:([^/]+)}) do
          plugin = Lux::PLUGINS[$1]
          die "Plugin %s not loaded, I have %s" % [$1, Lux::PLUGINS.keys.join(', ')] unless plugin
          plugin
        end
      else
        source = Lux.root.join('app/assets/%s' % source).to_s
      end
    end

    @source = Pathname.new source
    @opts   = opts

    @cache = Pathname.new './tmp/assets/%s' % source.gsub('/','-')
  end

  def compile
    case @source.to_s.split('.').last.downcase.to_sym
      when :coffee
        cached? || compile_coffee
      when :scss
        cached? || compile_sass
      when :js
        ";\n%s\n;" % @source.read
      else
        @source.read
    end
  end

  def content_type
    @ext ||= @source.to_s.split('.').last.to_sym

    [:css, :scss].include?(@ext) ? 'text/css' : 'text/javascript'
  end

  ###

  private

  def cached?
    @cache.exist? && (@cache.ctime > @source.ctime) ? @cache.read : false
  end

  def compile_coffee
    coffee_path = './node_modules/coffee-script/bin/coffee'
    coffee_opts = @opts[:production] ? '-cp' : '-Mcp --no-header'

    SimpleAssets.run "#{coffee_path} #{coffee_opts} '#{@source}' > '#{@cache}'", @cache

    data = @cache.read
    data = data.gsub(%r{//#\ssourceURL=[\w\-\.\/]+/app/assets/}, '//# sourceURL=/raw_asset/')

    @cache.write data

    data
  end

  def compile_sass
    node_sass = './node_modules/node-sass/bin/node-sass'
    node_opts = @opts[:production] ? '--output-style compressed' : '--source-comments'
    SimpleAssets.run "#{node_sass} #{node_opts} '#{@source}' '#{@cache}'", @cache
    @cache.read
  end
end
