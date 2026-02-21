class Hash
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

  # Hash#stringify_keys, #symbolize_keys, #slice, #slice!, #except, #except!,
  # #transform_keys - removed; all built-in since Ruby 2.5–3.0.

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

