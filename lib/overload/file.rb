class File
  class << self
    def write(name, data)
      File.open(name, 'w') { |f| f.write(data) }
      data
    end

    def change(name)
      data = File.read(name)
      data = yield data
      File.write(name, data)
    end
  end
end