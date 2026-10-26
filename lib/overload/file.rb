require 'fileutils'

class File
  class << self
    # write and create dir
    def write_p file, data
      FileUtils.mkdir_p File.dirname(file.to_s)
      write file, data
      data
    end

    def append path, content
      File.open(path, 'a') do |f|
        f.flock File::LOCK_EX
        f.puts content
      end
    end

    def delete? path
      if File.exist?(path)
        File.delete path
        true
      else
        false
      end
    end
  end
end
