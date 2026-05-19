class Lux::Type::UuidType < Lux::Type
  error :en, :invalid_uuid, 'is not a valid UUID'

  def coerce
    value { |data| data.to_s.strip.downcase }

    error_for(:invalid_uuid) unless value =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
  end

  def db_schema
    [:string, { limit: 36 }]
  end
end
