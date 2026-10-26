require 'fileutils'

class Pathname
  def touch
    FileUtils.touch to_s
  end

  def write_p data
    File.write_p to_s, data
  end

  # Lux.fw_root.join('plugins').folders do |folder| ...
  def folders
    Dir.folders to_s
  end

  def files
    Dir.files to_s
  end
end
