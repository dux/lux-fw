class Lux::Type::FloatType < Lux::Type
  opts :min, 'Minimum value'
  opts :max, 'Maximum value'
  opts :round, 'Round to (decimal spaces)'

  def coerce
    if opts[:round]
      value { |data| data.to_f.round(opts[:round]) }
    else
      value { |data| data.to_f }
    end

    error_for(:min_value_error, opts[:min], value) if opts[:min] && value < opts[:min]
    error_for(:max_value_error, opts[:max], value) if opts[:max] && value > opts[:max]
  end

  def db_schema
    [:float, {}]
  end
end
