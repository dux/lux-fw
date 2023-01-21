require 'fileutils'

class Pathname
  def touch
    FileUtils.touch to_s
  end

  def write_p data
    File.write_p to_s, data
  end
end
