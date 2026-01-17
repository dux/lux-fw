class Current
  def self.method_missing mame, *args
    Current.define_singleton_method(mame) { |*list| Lux.current.send(mame, *list) }
    Current.send mame, *args
  end
end
