class Lux::Type::TimezoneType < Lux::Type
  error :en, :invalid_time_zone, 'Invalid time zone'

  def coerce
    TZInfo::Timezone.get(value)
  rescue TZInfo::InvalidTimezoneIdentifier
    error_for :invalid_time_zone
  end

  def db_schema
    [:string, { limit: 50 }]
  end
end
