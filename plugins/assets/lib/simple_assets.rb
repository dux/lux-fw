require 'pathname'
require 'open3'

class SimpleAssets
  attr :files

  def self.run what, cache_file=nil
    puts what.yellow

    stdin, stdout, stderr, wait_thread = Open3.popen3(what)

    error = stderr.gets
    while line = stderr.gets do
      error += line
    end

    # node-sass prints to stderror on complete
    error = nil if error && error.index('Rendering Complete, saving .css file...')

    if error
      cache_file.unlink if cache_file && cache_file.exist?

      puts error.red
    end
  end

  ###

  def initialize target
    @base   = Dir['app/assets/%s/index.*' % target].first ||  die("Base index file not found for #{target} assets")
    @type   = [:css, :scss].include?(@base.split('.').last.to_sym) ? :css : :js
    @target = target
    @source = [Lux.root, target].join('/app/assets/') # assets root dir as js/main
    @files  = []

    load_files
  end

  def load_files
    for line in File.read(@base).split($/)
      line.sub!(%{^//=}, '#=')
      break unless line.sub!(%r{^#=\s}, '')
      add line.chomp
    end

    @files += [Lux.root.join(@base).to_s]
  end

  # adds file or list of files
  # add 'plugin:js_widgets/*'
  # add 'js/vendor/*'
  # add 'index.coffee'
  def add files
    if files.starts_with?('plugin:')
      plugin  = files.split('plugin:').last.chomp
      plugin  = Lux::PLUGINS[plugin] || die("Plugin %s not loaded, I have %s" % [plugin, Lux::PLUGINS.keys.join(', ')])
      files = Dir['%s/assets/%s/*' % [plugin, @type]]

      dir 'No files found in %s' % plugin unless files.first

      @files += files
    else
      files  = files.sub(/^\.\//,'')
      path   = files[0,1] == '/' ? "#{Lux.root}/app/assets#{files}" : [@source, files].join('/')
      @files += Dir[path].sort
    end

    @files = @files.select do |f|
      name = f.split('/').last
      name.include?('.') && !name.starts_with?('!')
    end
  end

  # retuns list of file ready for include in <script tag
  def dev_sources
    @files.map do |path|
      ext = path.split('.').last.to_sym

      if path.include?('/plugins/')
        'plugin:' + path.split('/plugins/', 2).last
      elsif path.include?('/app/assets/')
        '%s' % path.split('/app/assets/').last
      else
        path
      end
    end
  end

  def update_manifest
    manifest = Lux.root.join('public/manifest.json')
    manifest.write '{"files":{}}' unless manifest.exist?

    json = JSON.load manifest.read

    asset = '/assets/%s' % @asset

    return if json['files'][@target] == asset

    json['files'][@target] = asset

    manifest.write JSON.pretty_generate(json)
  end

  def minify
    asset = 'public/assets/%s' % @asset

    if @type == :js
      SimpleAssets.run './node_modules/minifier/index.js --no-comments -o "%{file}" "%{file}"' % { file: asset }
    end
  end

  # renders production ready file
  def render
    data = []

    data.push '// unminified'

    data = @files.inject([]) do |list, file|
      asset = SimpleAssets::Asset.new file, production: true
      list.push asset.compile
    end.join($/)

    @asset = @target.sub('/', '-') + '-' + Crypt.sha1(data) + '.' + @type.to_s
    local  = './public/assets/%s' % @asset

    Dir.mkdir('public/assets') unless Dir.exists?('public/assets')
    File.write(local, data)

    update_manifest
    minify

    SimpleAssets.run 'touch -t 201001010101 %s' % local
    SimpleAssets.run 'gzip -k %s' % local

    @asset
  end

end
