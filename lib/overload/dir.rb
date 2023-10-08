class Dir
  # Get list of folders in a folder
  # `Dir.folders('./app/assets')`
  def self.folders dir
    dir = dir.to_s

    (Dir.entries(dir) - ['.', '..'])
      .sort
      .select { |el| File.directory?([dir, el].join('/')) }
  end

  # Get all files in a folder
  # `Dir.files('./app/assets')`
  def self.files dir, opts = {}
    dir = dir.to_s
 
    list = (Dir.entries(dir) - ['.', '..'])
      .sort
      .reject { |el| File.directory?([dir, el].join('/')) }

    if opts[:ext] == false
      list = list.map{|f| f.sub(/\.\w+$/, '') }
    end

    list
  end

  # Find files in child folders.
  # All lists are allways sorted with idempotent function response.
  # Example: get all js and coffee in ./app/assets and remove ./app and invert folder search list
  # `Dir.find('./app/assets', ext: [:js, :coffee], root: './app', hash: true, invert: true)`
  # shortuct to remove ./app and not use root param
  # `Dir.find('./app#assets', ext: [:js, :coffee])`
  def self.find dir_path, opts={}
    opts[:ext] ||= []
    opts[:ext] = [opts[:ext]] unless opts[:ext].is_a?(Array)
    opts[:ext] = opts[:ext].map(&:to_s)

    parts = dir_path.to_s.split('#')

    if parts[1]
      opts[:root] = parts[0] + '/'
      dir_path = dir_path.to_s.sub('#', '/')
    end

    glob = []
    glob.push 'echo'

    folders = ['%s/*' % dir_path]

    unless opts[:shallow]
      folders.push '%s/*/*'           % dir_path
      folders.push '%s/*/*/*'         % dir_path
      folders.push '%s/*/*/*/*'       % dir_path
      folders.push '%s/*/*/*/*/*'     % dir_path
      folders.push '%s/*/*/*/*/*/*'   % dir_path
      folders.push '%s/*/*/*/*/*/*/*' % dir_path
    end

    folders = folders.reverse if opts[:invert]

    glob += folders

    glob.push "| tr ' ' '\n'"

    files = `cd #{Dir.pwd} && #{glob.join(' ')}`
      .split("\n")
      .reject { |_| _.include?('/*') }
      .select { |_| _ =~ /\.\w+$/ }
      .select { |_| opts[:ext].first ? opts[:ext].include?(_.split('.').last) : true }
      .map { |_| opts[:root] ? _.sub(opts[:root], '') : _ }

    if opts[:hash]
      files = files.map do |full|
        parts  = full.split('/')
        file   = parts.pop
        fparts = file.split('.')

        {
          full: full,
          dir: parts.join('/'),
          file: file,
          ext: fparts.pop,
          name: fparts.join('.')
        }.to_hwia
      end
    end

    if block_given?
      files.map { |f| yield(f).gsub('%s', f) }.join(opts[:join] || $/)
    else
      files
    end
  end

  # Requires all found ruby files in a folder, deep search into child folders
  # `Dir.require_all('./app')`
  def self.require_all folder
    list = Dir.find(folder, ext: :rb) unless list.is_a?(Array)
    list
      .select{ |o| o.index('.rb') }
      .each do |ruby_file|
        begin
          require ruby_file
        rescue Exception => error
          Lux.info "Dir.require_all('#{folder}') # error in #{ruby_file}"
          raise error
        end
      end
  end

  def self.mkdir? name
    FileUtils.mkdir_p name
  end
end

class Pathname
  # Lux.fw_root.join('plugins').folders do |folder| ...
  def folders
    Dir.folders to_s
  end

  # Lux.fw_root.join('plugins').folders do |folder| ...
  def files
    Dir.files to_s
  end
end
