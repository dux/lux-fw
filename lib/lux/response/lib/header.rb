
class Lux::Response::Header
  attr_reader :data

  def initialize
    @data = {}
  end

  def [] key
    @data[key.downcase]
  end

  def []= key, value
    @data[key.downcase] = value
  end

  def to_h
    @data.to_h.sort.to_h
  end

end