require_relative 'string_type'

class Lux::Type::TextType < Lux::Type::StringType
  opts :min, 'Minimum string length'
  opts :max, 'Maximum string length'

  def coerce
    value(&:to_s)
    value(&:downcase) if opts[:downcase]

    error_for(:min_length_error, opts[:min], value.length) if opts[:min] && value.length < opts[:min]
    error_for(:max_length_error, opts[:max], value.length) if opts[:max] && value.length > opts[:max]
  end

  def db_schema
    [:text, {}]
  end
end
