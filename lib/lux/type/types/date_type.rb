class Lux::Type::DateType < Lux::Type
  opts :min, 'Smallest date-time allowed'
  opts :max, 'Maximal date-time allowed'

  error :en, :invalid_date, 'is not a valid date'
  error :en, :min_date, 'Minimal allowed date is %s'
  error :en, :max_date, 'Maximal allowed date is %s'

  def coerce
    unless [Date].include?(value.class)
      begin
        value { |data| DateTime.parse(data.to_s) }
      rescue Date::Error, ArgumentError
        error_for(:invalid_date)
      end
    end

    value { |data| Date.new(data.year, data.month, data.day) }

    check_date_min_max
  end

  def db_schema
    [:date, {}]
  end

  private

  def check_date_min_max
    current = value.to_datetime
    if (min = opts[:min]) && (min = as_datetime(min)) > current
      error_for(:min_date, min.strftime('%Y-%m-%d'))
    end
    if (max = opts[:max]) && current > (max = as_datetime(max))
      error_for(:max_date, max.strftime('%Y-%m-%d'))
    end
    value
  end

  def as_datetime v
    v.is_a?(::Date) || v.is_a?(::Time) ? v.to_datetime : DateTime.parse(v.to_s)
  end
end
