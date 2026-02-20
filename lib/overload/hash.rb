class Hash
  def blank?
    self.keys.count == 0
  end

  def to_query namespace=nil
    keys = self.keys.sort

    return unless keys.first

    '?' + keys.map do |k|
      name = namespace ? "#{namespace}[#{k}]" : k
      "#{name}=#{CGI::escape(self[k].to_s)}"
    end.join('&')
  end

  def to_attributes
    self.keys.sort.map{ |k| '%s="%s"' % [k, self[k].to_s.gsub('"', '&quot;')]}.join(' ')
  end

  def to_css
    self.keys.sort.map{ |k| '%s: %s;' % [k, self[k].to_s.gsub('"', '&quot;')]}.join(' ')
  end

  def deep_sort
    keys.sort.each_with_object({}) do |k, h|
      v = self[k]
      h[k] =
        case v
        when Hash
          v.deep_sort
        when Array
          v.map { |e| e.is_a?(Hash) ? e.deep_sort : e }
        else
          v
        end
    end
  end

  def pluck *args
    string_args = args.map(&:to_s)
    self.select{ |k,v| string_args.index(k.to_s) }
  end

  def stringify_keys
    transform_keys { |key| key.to_s }
  end

  def symbolize_keys
    transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
  end

  # Hash#slice is built-in since Ruby 2.5 - removed custom implementation.

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

  def remove_empty covert_to_s = false
    self.keys.inject({}) do |t, el|
      v = self[el]
      t[covert_to_s ? el.to_s : el] = v if el.present? && v.present?
      t
    end
  end

  def to_js opts = {}
    data = opts[:empty] ? self : remove_empty
    data = data.to_json.gsub(/"(\w+)":/, "\\1:")
    data = data.gsub(/",(\w)/, '", \1') unless opts[:narrow]
    data
  end

  def transform_keys &block
    if block
      Hash.new.tap do |result|
        for key, value in self
          value = value.transform_keys(&block) if value.is_a?(Hash)
          result[block.call(key)] = value
        end
      end
    else
      enum_for(:transform_keys)
    end
  end

  # clean empty values from hash, deep
  def deep_compact value = nil
    value ||= self

    res_hash = value.map do |key, value|
      value = deep_compact(value) if value.is_a?(Hash)

      # we need to remove '0' because that is what empty checkbox inserts, but it is nil
      value = nil if [{}, [], '0'].include?(value)
      value = nil if value.blank?
      [key, value]
    end

    res_hash.to_h.compact
  end

  def self.deep_compact value
    (value || {}).deep_compact
  end

  def html_safe key
    if data = self[key]
      self[key] = data.html_safe
    end
  end
end

