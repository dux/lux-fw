class MiniAssets::Asset
  def self.call source
    ext  = source.split('.').last
    base = ['css', 'sass', 'scss'].include?(ext) ? MiniAssets::Asset::Css : MiniAssets::Asset::Js
    base.new source
  end

  def initialize source
    @ext    = source.split('.').last.to_sym
    @source = opts.app_root.join source
    @target = opts.public_root.join source

    cache_file = source.gsub('/', '-')

    if environment_prefix?
      prefix     = opts.production? ? :p : :d
      cache_file = '%s-%s' % [prefix, cache_file]
    end

    @cache = opts.tmp_root.join cache_file
  end

  def opts
    MiniAssets::Opts
  end

  def environment_prefix?
    false
  end

  def run! what
    puts what.yellow

    stdin, stdout, stderr, wait_thread = Open3.popen3(what)

    error = stderr.gets
    while line = stderr.gets do
      error += line
    end

    # node-sass prints to stderror on complete
    error = nil if error && error.index('Rendering Complete, saving .css file...')

    if error
      @cache.unlink if @cache.exist?

      puts error.red
    end
  end

  def comment text
    '/* %s */' % text
  end

  def cached?
    @cache.exist? && @cache.ctime > @source.ctime
  end

  def render
    func = 'compile_%s' % @ext

    # if custom method exists, execute it and return cache
    # othervise just read source
    if respond_to?(func)
      send func unless cached?
      @cache.read
    else
      @source.read
    end
  end
end

