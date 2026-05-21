class Lux::Type::IntegerType < Lux::Type
  opts :min, 'Minimum value'
  opts :max, 'Maximum value'

  def coerce
    value(&:to_i)
    check_min_max
  end

  def db_schema
    [:integer, {}]
  end
end
