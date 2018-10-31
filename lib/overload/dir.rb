class Dir
  # get only folder list form a folder
  def self.folders dir
    dir = dir.to_s

    files = Dir
      .entries(dir)
      .drop(2)
      .select { |el| File.directory?([dir, el].join('/')) }

    # call block on each if block given
    files.each { |dir| yield(dir) } if block_given?

    files
  end
end

class Pathname
  # Lux.fw_root.join('plugins').folders do |folder| ...
  def folders &block
    Dir.folders(self.to_s, &block)
  end
end