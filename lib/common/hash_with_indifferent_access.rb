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
    check_fix(out)
  end

  def []= key, value
    super key.to_s, check_fix(value)
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

  def merge h
    out = dup
    h.each { |k,v| out[k] = v }
    out
  end

  def merge! h
    h.each { |k,v| self[k] = v }
  end

  private

  def check_fix value
    value.class == Hash ? self.class.new(value) : value
  end
end
