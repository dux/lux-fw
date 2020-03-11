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

  # Gobs files search into child folders.
  # All lists are allways sorted with idempotent function response.
  # Example: get all js and coffee in ./app/assets and remove ./app
  # `Dir.all_files('./app/assets', ext: [:js, :coffee], root: './app')`
  def self.all_files dir_path, opts={}
    opts[:ext] ||= []
    opts[:ext] = [opts[:ext]] unless opts[:ext].is_a?(Array)
    opts[:ext] = opts[:ext].map(&:to_s)

    glob = []
    glob.push 'echo'
    glob.push '%s/*'             % dir_path
    glob.push '%s/*/*'           % dir_path
    glob.push '%s/*/*/*'         % dir_path
    glob.push '%s/*/*/*/*'       % dir_path
    glob.push '%s/*/*/*/*/*'     % dir_path
    glob.push '%s/*/*/*/*/*/*'   % dir_path
    glob.push '%s/*/*/*/*/*/*/*' % dir_path
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
    list = Dir.all_files(list, ext: :rb) unless list.is_a?(Array)
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