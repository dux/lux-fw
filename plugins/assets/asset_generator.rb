module AssetGenerator
  extend self

  def mask_glob path, mask
    path = path.to_s
    out  = nil

    Dir.chdir(@folder) do
      out = Dir[path]
        .select { |it| File.file?(it) }
        .reject { |it| it.ends_with?('.template') }
        .sort
        .map do |it|
          it = it.sub(@folder, '.')
          mask % it
        end
        .join($/)
    end

    %[/* mask_glob "#{path}" */\n#{out}]
  end

  # find .templates files and process them
  def process_templates folder=nil
    folder ||= './app'
    folder += '/**/*.template' unless folder.include?('.template')

    for file in Dir[folder]
      parse_template file
    end
  end

  # process single template
  def parse_template template_location
    begin
      @folder = template_location.sub(%r{/[^/]+$}, '')
      local   = template_location.sub('.template', '')
      data    = ERB.new(File.read(template_location)).result
      data    = "/* Generated from #{template_location.split('/').last} */\n\n#{data}"
      File.write(local, data)
    rescue => e
      puts "#{template_location}\n\n#{e.message}\n\n#{e.backtrace.join($/)}".red
    end
  end

  # relative path JS require from single a folder
  def require path
    mask_glob path, 'require("%s");'
  end

  # relative path CSS import from single a folder
  def import path
    mask_glob path, '@import "%s";'
  end

  def grep mask
    Dir[mask]
      .map{ |it| it.split('/').last }
      .map{ |it| yield(it) }
      .join($/)
  end

  # absolute file search for CSS import
  def import_find folder
    import_require_find 'CSS import glob', '@import "%s/%s";', folder do |it|
      it.ends_with?('css')
    end
  end

  # absolute file search for JS import
  def require_find folder
    import_require_find 'JS require glob', 'require("%s/%s");', folder do |it|
      it.ends_with?('js') || it.ends_with?('coffee')
    end
  end

  private

  def import_require_find name, mask, folder, &test
    die "folder must start with / (we search from app root)" unless folder.starts_with?('/')
    die "glob * is not require" if folder.include?('*')

    folder = folder.sub('/', '')

    files = `find #{folder}`
      .split($/)
      .select(&test)

    prefix = @folder
      .sub('./', '')
      .split('/')
      .map { '..' }
      .join('/')

    out = [%{/* #{name} "/#{folder}" */}]

    for file in files
      out.push mask % [prefix, file.sub(/^\.\//, '')]
    end

    out.join($/)
  end
end