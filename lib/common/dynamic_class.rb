# o = DynamicClass.new name: 'a'
# o.name -> 'a'
# o.name = 'b'
# o.name 'b'
# o.name -> 'b'
# o.name = nil
# o.name -> nil
# o.title -> raises error
class DynamicClass
  def initialize data, &block
    @data  = data
    @block = block if block
  end

  def method_missing m, arg=:_UNDEF
    key = m.to_s.sub('=','').to_sym

    unless @data.has_key?(key)
      raise ArgumentError.new('Key :%s not found in DynamicOptions' % key)
    end

    if arg == :_UNDEF
      @data[key]
    else
      @data[key] = arg
    end
  end
end
