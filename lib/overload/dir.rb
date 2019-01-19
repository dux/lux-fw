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
end

class Pathname
  # Lux.fw_root.join('plugins').folders do |folder| ...
  def folders &block
    Dir.folders(to_s, &block)
  end
end