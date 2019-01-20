class HashWithIndifferentAccess < Hash
  def initialize data={}
    unless data.class == Hash
      raise ArgumentError.new('Expected "Hash", not "%s"' % data.class)
    end

    data.each do |key, value|
      self[key.to_s] = value
    end
  end

  def [] key
    out = super key.to_s
    out.class == Hash ? self.class.new(out) : out
  end

  def []= key, value
    super key.to_s, value
  end

  def key? key
    super key.to_s
  end
  alias_method :include?, :key?
  alias_method :has_key?, :key?
  alias_method :member?, :key?

  def delete key
    super key.to_s
  end

  def dig *args
    out = self

    while key = args.shift
      out = out[key]
    end

    out
  end

end
