require_relative 'string_type'

class Lux::Type::TextType < Lux::Type::StringType
  def coerce
    value(&:to_s)
    value(&:downcase) if opts[:downcase]
    check_min_max_length
  end

  def db_schema
    [:text, {}]
  end
end
