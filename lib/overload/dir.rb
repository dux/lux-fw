class Dir
  # Get list of folders in a folder
  # `Dir.folders('./app/assets')`
  def self.folders dir
    dir = dir.to_s

    Dir
      .entries(dir)
      .reject { |el| ['.', '..'].include?(el) }
      .select { |el| File.directory?([dir, el].join('/')) }
      .sort
  end

  # Get all files in a folder
  # `Dir.files('./app/assets')`
  def self.files dir
    dir = dir.to_s

    Dir
      .entries(dir)
      .drop(2)
      .reject { |el| File.directory?([dir, el].join('/')) }
      .sort
  end

  # Find files in child folders.
  # All lists are allways sorted with idempotent function response.
  # Example: get all js and coffee in ./app/assets and remove ./app
  # `Dir.find('./app/assets', ext: [:js, :coffee], root: './app')`
  # shortuct to remove ./app
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
    glob.push '%s/*'             % dir_path

    unless opts[:shallow]
      glob.push '%s/*/*'           % dir_path
      glob.push '%s/*/*/*'         % dir_path
      glob.push '%s/*/*/*/*'       % dir_path
      glob.push '%s/*/*/*/*/*'     % dir_path
      glob.push '%s/*/*/*/*/*/*'   % dir_path
      glob.push '%s/*/*/*/*/*/*/*' % dir_path
    end

    glob.push "| tr ' ' '\n'"

    `#{glob.join(' ')}`
      .split("\n")
      .reject { |_| _.include?('/*') }
      .select { |_| _ =~ /\.\w+$/ }
      .select { |_| opts[:ext].first ? opts[:ext].include?(_.split('.').last) : true }
      .map { |_| opts[:root] ? _.sub(opts[:root], '') : _ }
  end

  # Requires all found ruby files in a folder, deep search into child folders
  # `Dir.require_all('./app')`
  def self.require_all list
    list = Dir.find(list, ext: :rb) unless list.is_a?(Array)
    list
      .select{ |o| o.index('.rb') }
      .each { |ruby_file| require ruby_file }
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