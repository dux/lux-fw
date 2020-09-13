# frozen_string_literal: true

class Hash
  def blank?
    self.keys.count == 0
  end

  def to_query namespace=nil
    keys = self.keys.sort

    return unless keys.first

    '?' + keys.sort.map do |k|
      name = namespace ? "#{namespace}[#{k}]" : k
      "#{name}=#{CGI::escape(self[k].to_s)}"
    end.join('&')
  end

  def data_attributes
    self.keys.sort.map{ |k| 'data-%s="%s"' % [k, self[k].to_s.gsub('"', '&quot;')]}.join(' ')
  end

  def pluck *args
    string_args = args.map(&:to_s)
    self.select{ |k,v| string_args.index(k.to_s) }
  end

  def transform_keys &block
    return enum_for(:transform_keys) unless block_given?
    result = Hash.new
    for key, value in self
      value = value.transform_keys(&block) if value.is_a?(Hash)
      result[block.call(key)] = value
    end
    result
  end

  def stringify_keys
    transform_keys { |key| key.to_s }
  end

  def symbolize_keys
    transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
  end

  def pretty_generate
    JSON.pretty_generate(self).gsub(/"([\w\-]+)":/) { %["#{$1.yellow}":] }
  end

  # Returns hash with only se
  def slice *keys
    keys.map! { |key| convert_key(key) } if respond_to?(:convert_key, true)
    keys.each_with_object(self.class.new) { |k, hash| hash[k] = self[k] if has_key?(k) }
  end

  def slice! *keys
    keys.map! { |key| convert_key(key) } if respond_to?(:convert_key, true)
    omit = slice(*self.keys - keys)
    hash = slice(*keys)
    hash.default      = default
    hash.default_proc = default_proc if default_proc
    replace(hash)
    omit
  end

  # Returns a hash that includes everything but the given keys.
  #    hash = { a: true, b: false, c: nil}
  #    hash.except(:c) # => { a: true, b: false}
  #    hash # => { a: true, b: false, c: nil}
  #
  # This is useful for limiting a set of parameters to everything but a few known toggles:
  #    @person.update(params[:person].except(:admin))
  def except(*keys)
    dup.except!(*keys)
  end

  # Hash#except in place, modifying current hash
  def except!(*keys)
    keys.each { |key| delete(key.to_s); delete(key.to_sym)  }
    self
  end

  def remove_empty
    self.keys.inject({}) do |t, el|
      v = self[el]
      t[el] = v if v.present?
      t
    end
  end
end

