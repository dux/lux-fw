module LuxJson
  # to json smart - pretty in dev
  def to_jsons
    Lux.env.log? ? to_jsonp : to_json
  end

  # to json pretty
  def to_jsonp colorize_keys = false
    out = JSON.pretty_generate(self)
    colorize_keys ? out.gsub(/(\n\s|)"([\w\-]+)":/) { '%s"%s":' % [$1, $2.colorize(:yellow)] } : out
  end

  # to json compact (for javascript)
  def to_jsonc
    to_json.gsub(/"(\w+)":/, '\1:')
  end
end

class Hash
  include LuxJson
end

class Array
  include LuxJson
end

