class File
  class << self
    def change name
      data = File.read(name)
      data = yield data
      File.write(name, data)
    end
  end
end