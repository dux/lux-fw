# Lux::Type::RefType - 16-char opaque ID stored as varchar(20)
class Lux::Type::RefType < Lux::Type
  def coerce
    value { |data| data.to_s }
    error_for(:unallowed_characters_error) unless value =~ /^\w+$/
    error_for(:max_length_error, 16, value.length) unless value.length == 16
  end

  def db_schema
    [:string, { limit: 20 }]
  end
end
