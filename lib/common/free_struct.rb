# o = FreeStruct.new name: 'a'
# o.name -> 'a'
# o.name = 'b'
# o.name 'b'
# o.name -> 'b'
# o.name = nil
# o.name -> nil
# o.title -> raises error

class FreeStruct
  def initialize hash
    hash.each do |key, value|
      ivar = "@#{key}"

      instance_variable_set ivar, value

      define_singleton_method(key) do
        instance_variable_get ivar
      end

      define_singleton_method "#{key}=" do |val|
        instance_variable_set ivar, val
      end
    end
  end

  def [] key
    instance_variable_get "@#{key}"
  end
end
