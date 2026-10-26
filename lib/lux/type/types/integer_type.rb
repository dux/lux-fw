class Lux::Type::IntegerType < Lux::Type
  opts :min, 'Minimum value'
  opts :max, 'Maximum value'

  error :en, :not_integer_error, 'is not a whole number'

  def coerce
    value { |d| d.is_a?(::Numeric) ? d.to_i : (Integer(d.to_s, 10) rescue error_for(:not_integer_error)) }
    check_min_max
  end

  def db_schema
    [:integer, {}]
  end
end
