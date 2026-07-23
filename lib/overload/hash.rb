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

  # Recursively convert keys to strings (nested Hash + Array of Hash).
  def deep_stringify_keys
    each_with_object({}) do |(k, v), h|
      h[k.to_s] =
        case v
        when Hash
          v.deep_stringify_keys
        when Array
          v.map { |e| e.is_a?(Hash) ? e.deep_stringify_keys : e }
        else
          v
        end
    end
  end

  def deep_stringify_keys!
    replace deep_stringify_keys
  end

  # Recursively convert keys to symbols (nested Hash + Array of Hash).
  def deep_symbolize_keys
    each_with_object({}) do |(k, v), h|
      h[k.to_sym] =
        case v
        when Hash
          v.deep_symbolize_keys
        when Array
          v.map { |e| e.is_a?(Hash) ? e.deep_symbolize_keys : e }
        else
          v
        end
    end
  end

  def deep_symbolize_keys!
    replace deep_symbolize_keys
  end

  def pluck *args
    string_args = args.map(&:to_s)
    self.select{ |k,v| string_args.index(k.to_s) }
  end

  # Hash#slice, #slice!, #except, #except!, #transform_keys - built-in since Ruby 2.5–3.0.
  # Shallow stringify_keys / symbolize_keys: use transform_keys(&:to_s) / transform_keys(&:to_sym).

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

  def reverse_merge other
    other.merge(self)
  end
  alias :with_defaults :reverse_merge

  def reverse_merge! other
    replace(other.merge(self))
  end
  alias :with_defaults! :reverse_merge!

  def html_safe key
    if data = self[key]
      self[key] = data.html_safe
    end
  end

  # `attrs.tag(:div, 'inner')` -> '<div ...>inner</div>'. The receiver is the
  # attributes hash. Provided by the vendored html-tag (see lib/lux/utils/html_tag/).
  def tag(node_name, inner = nil, &block)
    inbound = HtmlTag::Inbound.new
    inbound.tag(node_name, inner, **self, &block)
    inbound.render
  end
end

