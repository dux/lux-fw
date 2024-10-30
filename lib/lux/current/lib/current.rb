class Current
  def self.method_missing mame, *args
    eval "def Current.#{mame} *list; Lux.current.#{mame} *list; end"
    Current.send mame, *args
  end
end
