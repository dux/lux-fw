module Lux
  # check and coerce value
  # Lux.type(:label) -> Lux::Type::LabelType
  # Lux.type(:label, 'Foo bar') -> "foo-bar"
  def type klass_name, value = UNSET, opts = {}, &block
    klass = Lux::Type.load(klass_name)

    if value.equal?(UNSET)
      klass
    else
      begin
        check = klass.new value, opts
        check.get
      rescue TypeError => error
        if block
          block.call error
          false
        else
          raise error
        end
      end
    end
  end
end
