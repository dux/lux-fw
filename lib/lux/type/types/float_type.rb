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

    check_min_max
  end

  def db_schema
    [:float, {}]
  end
end
