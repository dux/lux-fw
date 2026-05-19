require_relative 'date_type'

class Lux::Type::DatetimeType < Lux::Type::DateType
  opts :min, 'Smallest date allowed'
  opts :max, 'Maximal date allowed'

  error :en, :invalid_datetime, 'is not a valid datetime'

  def coerce
    unless [Time, DateTime].include?(value.class)
      begin
        value { |data| DateTime.parse(data.to_s) }
      rescue Date::Error, ArgumentError
        error_for(:invalid_datetime)
      end
    end

    check_date_min_max
  end

  def db_schema
    [:timestamp]
  end
end
