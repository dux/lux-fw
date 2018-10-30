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
  ASSETS_DATA ||= { js: {}, css: {} }
  ASSET_TYPES ||= {
    js:  ['js', 'coffee'],
    css: ['css', 'scss']
  }

  @@compile   = nil

  class << self
    def configure &block
      class_eval &block
    end

    def run what, cache_file=nil
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

    def add_files ext, name, block
      @name = name = name.to_s
      return new ext, name if ASSETS_DATA[ext][@name]

      @files = []
      @ext   = ext
      class_eval &block
      ASSETS_DATA[ext][@name] = @files
    end

    def js name, &block
      add_files :js, name, block
    end

    def css name, &block
      add_files :css, name, block
    end

    def compile &block
      @@compile = block
    end

    # adds file or list of files
    # add 'plugin:js_widgets/*'
    # add 'js/vendor/*'
    # add 'index.coffee'
    def add files
      if files.is_a?(Array)
        add_local_files files
        return
      else
        files =
        if files[0,1] == '/' || files[0,2] == './'
          files
        else
          "./app/assets/#{files}"
        end

        if files.ends_with?('/*')
          files  = Dir["#{files}*/*"].sort
          files  = add_local_files files
        else
          # it will alert if file not found
          add_local_files [files]
        end

        die    'No files found in %s (%s :%s)' % [path, @ext, @name] unless files.first
      end
    end

    # plugin :foo, :bar
    def plugin *args
      for name in args.flatten
        plugin = Lux.plugin.get name
        add '%s/*' % plugin[:folder]
      end
    end

    def files name
      parts = name.split('/', 2)
      ASSETS_DATA[parts.first.to_sym][parts[1]]
    end

    def compile_all
      for ext in [:js, :css]
        for name in ASSETS_DATA[ext].keys
          path = LuxAssets.send(ext, name).compile

          yield "#{ext}/#{name}", path if block_given?
        end
      end
    end

    def add_local_files files
      files = files.select { |it| ASSET_TYPES[@ext].include?(it.split('.').last) }

      files = files.select do |f|
        name = f.split('/').last
        name.include?('.') && !name.starts_with?('!')
      end

      @files += files
      files
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

    die "No files found for [#{@ext}/#{@name}]" unless @files.try(:first)

    for file in @files
      @data.push LuxAssets::Asset.new(file, production: true).compile
    end

    send 'compile_%s' % @ext

    @asset_file
  end

  def files
    @files
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