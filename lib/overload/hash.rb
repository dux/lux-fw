class Hash
  def to_css
    self.keys.sort.map{ |k| '%s: %s;' % [k, self[k].to_s.gsub('"', '&quot;')]}.join(' ')
  end

  # Recursively remove the named keys from this hash and every nested hash
  # (Array-of-Hash included). Returns a new hash; deep_destroy! mutates in place.
  def deep_destroy *keys
    keys = keys.flatten.map(&:to_s)

    each_with_object({}) do |(k, v), h|
      next if keys.include?(k.to_s)

      h[k] =
        case v
        when Hash
          v.deep_destroy(*keys)
        when Array
          v.map { |e| e.is_a?(Hash) ? e.deep_destroy(*keys) : e }
        else
          v
        end
    end
  end

  def deep_destroy! *keys
    replace deep_destroy(*keys)
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

  # Hash#slice, #slice!, #except, #except!, #transform_keys - built-in since Ruby 2.5–3.0.
  # Shallow stringify_keys / symbolize_keys: use transform_keys(&:to_s) / transform_keys(&:to_sym).

  def remove_empty covert_to_s = false
    self.keys.inject({}) do |t, el|
      v = self[el]
      t[covert_to_s ? el.to_s : el] = v if el.present? && v.present?
      t
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

