class Lux::Type::StringType < Lux::Type
  opts :min, 'Minimum string length'
  opts :max, 'Maximum string length'
  opts :downcase, 'is the string in downcase?'
  opts :html, 'Stores real HTML: skips the `<` -> &LT; input escape'

  def coerce
    value(&:to_s)
    value(&:downcase) if opts[:downcase]
    value(&:html_escape) unless opts[:html]

    # default 255 matches the DB string limit
    check_min_max_length 255
  end

  def db_schema
    [:string, {
      limit: opts[:max] || 255
    }]
  end
end
