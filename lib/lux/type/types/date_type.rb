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

    value { |data| DateTime.new(data.year, data.month, data.day) }

    check_date_min_max
  end

  def db_schema
    [:date, {}]
  end

  private

  def check_date_min_max
    if min = opts[:min]
      min = DateTime.parse(min)
      error_for(:min_date, min) if min > value
    end

    if max = opts[:max]
      max = DateTime.parse(max)
      error_for(:max_date, max) if value > max
    end

    value
  end
end
