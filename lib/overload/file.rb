class File
  class << self
    # modify file data
    def change name
      data = File.read(name)
      data = yield data
      File.write(name, data)
    end

    # write and create dir
    def xwrite file, data
      path = file.split('/').reverse.drop(1).reverse.join('/')
      FileUtils.mkdir_p(path) unless File.exists?(path)
      self.write file, data
      data
    end
  end
end