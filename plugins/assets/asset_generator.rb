module AssetGenerator
  extend self

  # generic mask grep
  def grep files
    path = Pathname.new(@folder).join(files).to_s

    Dir[path]
      .map{ |it| it.split('/').last }
      .reject { |it| it.include?('!') }
      .map{ |it| yield(it) }
      .join($/)
  end

  # relative path JS require from single a folder
  def import path
    mask_glob path, 'import "%s";'
  end

  # absolute file search for JS import
  def import_find folder
    import_by_mask 'JS require glob', 'import "%s/%s";', folder do |it|
      it.ends_with?('js') || it.ends_with?('coffee')
    end
  end

  # relative path CSS import from single a folder
  def css_import path
    mask_glob path, '@import "%s";'
  end

  # absolute file search for CSS import
  def css_import_find folder
    import_by_mask 'CSS import glob', '@import "%s/%s";', folder do |it|
      it.ends_with?('css')
    end
  end

  def mask_glob path, mask
    path = path.to_s
    out  = nil

    Dir.chdir(@folder) do
      out = Dir[path]
        .select { |it| File.file?(it) }
        .reject { |it| it.include?('!') }
        .reject { |it| it.ends_with?('.erb') }
        .sort
        .map do |it|
          it = it.sub(@folder, '.')
          mask % it
        end
        .join($/)
    end

    raise 'No files found in "%s"' % path if out.blank?

    %[/* mask_glob "#{path}" */\n#{out}]
  end

  # find .erbs files and process them
  def process_templates folder=nil
    folder ||= './app/assets'
    folder += '/**/*.erb' unless folder.include?('.erb')

    for file in Dir[folder]
      puts 'Assets compile: %s' % file.green
      parse_template file
    end

    true
  end

  # process single template
  def parse_template template_location
    begin
      @folder = template_location.sub(%r{/[^/]+$}, '')
      local   = template_location.sub('.erb', '')
      data    = ERB.new(File.read(template_location)).result
      data    = "/* Generated from #{template_location.split('/').last} */\n\n#{data}"
      File.write(local, data)
    rescue => e
      puts "#{template_location}\n\n#{e.message}\n\n#{e.backtrace.join($/)}".red
    end
  end

  private

  def import_by_mask name, mask, folder, &test
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