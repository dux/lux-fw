# frozen_string_literal: true

class FolderModel

  class << self
    def find(key)
      new(key)
    end

    def all
      Dir["db/#{self.to_s.tableize}/*.json"].map{|file| new file.split('/').last.sub('.json') }
    end
  end

  ###

  def [](key)
    @data[key]
  end

  def []=(key, value)
    @data[key] = value
  end

  def method_missing(name, *args)
    func = name.to_s.split('=')[0].to_sym

    if name.to_s.index('=')
      @data[func] = args[0]
    else
      # raise "Field #{name} not found"
      @data[func]
    end
  end

  def save
    @storage.write JSON.pretty_generate(@data)
    @data
  end
  alias :save! :save

  def initialize(key)
    @key = key
    @storage = Pathname.new("db/#{self.class.to_s.tableize}/#{key}.json")
    @data = JSON.parse @storage.read
    @data = @data.h
  end

end

