require 'fileutils'

class Pathname
  def touch
    FileUtils.touch to_s
  end
end
