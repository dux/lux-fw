class Lux::Type::StringType < Lux::Type
  opts :min, 'Minimum string length'
  opts :max, 'Maximum string length'
  opts :downcase, 'is the string in downcase?'

  def coerce
    value(&:to_s)
    value(&:downcase) if opts[:downcase]

    # this is database default for string type and it is good to define default unless defined
    opts[:max] ||= 255

    error_for(:min_length_error, opts[:min], value.length) if opts[:min] && value.length < opts[:min]
    error_for(:max_length_error, opts[:max], value.length) if opts[:max] && value.length > opts[:max]
  end

  def db_schema
    [:string, {
      limit: @opts[:max] || 255
    }]
  end
end
