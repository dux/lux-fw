# LuxAssets.configure do
#   # admin
#   css :main do
#     add 'css/main/index.scss'
#   end

#   # cell
#   js :cell do
#     add ViewCell.all_js
#   end

#   # main
#   js :main do
#     add 'js/main/js/*'
#     add 'js/shared/*'
#     add 'plugin:js_widgets'
#   end
# ...

# LuxAssets.files('js/admin')
# LuxAssets.css(:admin).compile

# LuxAssets.css(:admin).compile_all do |name, path|
#   puts "Compile #{name} -> #{path}"
# end

require 'open3'

class LuxAssets
  ASSETS_DATA = { js: {}, css: {} } unless defined?(ASSETS_DATA)
  @@compile   = nil

  def self.configure &block
    class_eval &block
  end

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

  def self.add_files ext, name, block
    name = name.to_s
    return new ext, name if ASSETS_DATA[ext][name]

    @files = []
    @ext   = ext
    class_eval &block
    ASSETS_DATA[ext][name.to_s] = @files
  end

  def self.js name, &block
    add_files :js, name, block
  end

  def self.css name, &block
    add_files :css, name, block
  end

  def self.compile &block
    @@compile = block
  end

  # adds file or list of files
  # add 'plugin:js_widgets/*'
  # add 'js/vendor/*'
  # add 'index.coffee'
  def self.add files
    if files.is_a?(Array)
      @files += files
      return
    elsif files.starts_with?('plugin:')
      plugin  = files.split('plugin:').last.chomp
      plugin  = Lux::PLUGINS[plugin] || die("Plugin %s not loaded, I have %s" % [plugin, Lux::PLUGINS.keys.join(', ')])
      files = Dir['%s/assets/%s/*' % [plugin, @ext]]

      die 'No files found in %s' % plugin unless files.first

      @files += files
    else
      path =
      if files[0,1] == '/'
        files
      else
        "./app/assets/#{files}"
      end

      files  = Dir[path].sort

      die 'No files found in %s' % path unless files.first

      @files += files
    end

    @files = @files.select do |f|
      name = f.split('/').last
      name.include?('.') && !name.starts_with?('!')
    end
  end

  def self.files name
    parts = name.split('/', 2)
    ASSETS_DATA[parts.first.to_sym][parts[1]]
  end

  def self.compile_all
    for ext in [:js, :css]
      for name in ASSETS_DATA[ext].keys
        path = LuxAssets.send(ext, name).compile

        yield "#{ext}/#{name}", path if block_given?
      end
    end
  end

  ###

  def initialize ext, name
    @ext    = ext == :js ? :js : :css
    @name   = name
    @files  = ASSETS_DATA[ext][name]
    @target = "#{@ext}/#{@name}"
  end

  def js?
    @ext == :js
  end

  def css?
    @ext == :css
  end

  def compile
    @data = []

    for file in @files
      @data.push LuxAssets::Asset.new(file, production: true).compile
    end

    send 'compile_%s' % @ext

    @asset_file
  end

  ###

  private

  def save_data data
    @asset_file = '/assets/%s' % (@target.sub('/', '-') + '-' + Crypt.sha1(data) + '.' + @ext.to_s)
    @asset_path = "./public#{@asset_file}"

    File.write(@asset_path, data)

    if LuxAssets::Manifest.add(@target, @asset_file)
      yield

      LuxAssets.run 'touch -t 201001010101 %s' % @asset_path
      LuxAssets.run 'gzip -k %s' % @asset_path
    end
  end

  def compile_js
    save_data @data.join(";\n") do
      # minify
      LuxAssets.run './node_modules/minifier/index.js --no-comments -o "%{file}" "%{file}"' % { file: @asset_path }
    end
  end

  def compile_css
    save_data @data.join($/) do

    end
  end
end