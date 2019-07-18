# Convert hash to object with methods
#   o = FreeStruct.new :name, :surname
#   o = FreeStruct.new name: 'a'
#   o.name   -> 'a'
#   o[:name] -> 'a'
#   o.name = 'b'
#   o.name 'b'
#   o.name -> 'b'
#   o.name = nil
#   o.name -> nil
#   o.title -> raises error

class FreeStruct
  def initialize *hash
    if hash.first.class == Hash
      @hash = hash.first
    else
      @hash = hash.inject({}) { |h, el| h[el.to_sym] = nil; h }
    end
  end

  def [] key
    method_missing key
  end

  def []= key, value
    method_missing '%s=' % key, value
  end

  def method_missing name, value=nil
    name   = name.to_s
    is_set = !!name.sub!('=', '')
    name   = name.to_sym

    raise ArgumentError.new('Key %s not found' % name) unless @hash.has_key?(name)

    if is_set
      @hash[name] = value
    else
      @hash[name]
    end
  end

  def to_h
    @hash.dup
  end
end

