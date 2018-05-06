# o = DynamicClass.new name: 'a'
# o.name -> 'a'
# o[:name] -> 'a'
# o.name = 'b'
# o.name 'b'
# o.name -> 'b'
# o.name = nil
# o.name -> nil
# o.title -> raises error
class DynamicClass
  def initialize data
    @data  = data
  end

  def method_missing m, arg=:_UNDEF
    key = m.to_s.sub('=','').to_sym

    check_key_existance? key

    if arg == :_UNDEF
      @data[key]
    else
      @data[key] = arg
    end
  end

  def [] key
    check_key_existance? key
    @data[key]
  end

  def []= key, value
    check_key_existance? key
    @data[key] = value
  end

  def key? key
    @data.key?(key)
  end

  private

  def check_key_existance? key
    raise ArgumentError.new('Key :%s not found in DynamicOptions' % key) unless @data.has_key?(key)
  end
end
