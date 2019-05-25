class Dir
  # get only folder list form a folder
  def self.folders dir
    dir = dir.to_s

    Dir
      .entries(dir)
      .reject { |el| ['.', '..'].include?(el) }
      .select { |el| File.directory?([dir, el].join('/')) }
      .sort
  end

  # get files form a folder
  def self.files dir
    dir = dir.to_s

    Dir
      .entries(dir)
      .drop(2)
      .reject { |el| File.directory?([dir, el].join('/')) }
      .sort
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