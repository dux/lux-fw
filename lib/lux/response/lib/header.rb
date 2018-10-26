
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

  def merge hash
    for key, value in hash
      @data[key.downcase] = value
    end

    @data
  end

  def delete name
    @data.delete name.downcase
  end

  def to_h
    # data['Set-Cookie'] = data.delete('set-cookie') if data['set-cookie']
    @data#.to_h.sort.to_h
  end

end