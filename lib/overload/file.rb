class File
  class << self
    # write and create dir
    def write_p file, data
      path = file.split('/').reverse.drop(1).reverse.join('/')
      FileUtils.mkdir_p(path) unless File.exist?(path)
      self.write file, data
      data
    end

    def append path, content
      File.open(path, 'a') do |f|
        f.flock File::LOCK_EX
        f.puts content
      end
    end

    def ext name
      out = name.to_s.split('.').last.to_s.downcase
      [3,4].include?(out.length) ? out : nil
    end

    def delete? path
      if File.exist?(path)
        File.delete path
        true
      else
        false
      end
    end

    #  exit if File.is_locked?('tmp/test.lock')
    def is_locked? lock_file
      lock_fd = File.open(lock_file, File::RDWR|File::CREAT, 0644)

      Timeout::timeout(0.1) do
        lock_fd.flock(File::LOCK_EX)
        return false
      end
    rescue Timeout::Error
      return true
    end
  end
end
