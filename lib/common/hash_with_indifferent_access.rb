class HashWithIndifferentAccess
  def initialize data=nil
    @data = {}
    merge! data if data
  end

  def merge! data
    data.each { |key, value| @data[convert_key(key)] = convert_value(value) }
  end
  alias_method :update, :merge!

  def merge data
    copy = self.class.new @data
    copy.merge! data
    copy
  end

  def [] key
    @data[convert_key(key)]
  end

  def []= key, value
    @data[convert_key(key)] = convert_value(value)
  end
  alias_method :store, :[]=

  def key? name
    @data.key? convert_key(name)
  end
  alias_method :include?, :key?
  alias_method :has_key?, :key?
  alias_method :member?, :key?

  def to_json opts=nil
    @data.to_json opts
  end

  def delete_if &block
    @data.delete_if(&block)
  end

  def delete key
    @data.delete convert_key(key)
  end

  def dig *args
    list = args.map{ |it| it.class == Symbol ? it.to_s : it }
    @data.dig *list
  end

  def pluck *args
    args = args.map(&:to_s)
    @data.select { |k,v| args.include?(k) }
  end

  def clear
    @data.keys.each { |key| @data.delete(key) }
  end

  def each;    @data.each { |k,v| yield(k,v) }; end
  def keys;    @data.keys; end
  def values;  @data.keys; end
  def to_hash; @data; end

  private

  def convert_key key
    key.kind_of?(Symbol) ? key.to_s : key
  end

  def convert_value value
    value.is_a?(Hash) ? self.class.new(value) : value
  end
end
