class Current
  def self.method_missing name, *args
    Current.define_singleton_method(name) { |*list| Lux.current.send(name, *list) }
    Current.send name, *args
  end
end
