class Lux::Type::FloatType < Lux::Type
  opts :min, 'Minimum value'
  opts :max, 'Maximum value'
  opts :round, 'Round to (decimal spaces)'

  error :en, :not_number_error, 'is not a number'

  def coerce
    value do |d|
      num = d.is_a?(::Numeric) ? d.to_f : (Float(d.to_s) rescue error_for(:not_number_error))
      opts[:round] ? num.round(opts[:round]) : num
    end
    check_min_max
  end

  def db_schema
    [:float, {}]
  end
end
