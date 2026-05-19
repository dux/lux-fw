class Lux::Type::CountryType < Lux::Type
  def coerce
    @value = @value.to_s.upcase
  end

  def validate
    raise TypeError.new('Country sid must be exactly 2 characters') unless @value.length == 2
    raise TypeError.new(error_for(:unallowed_characters_error)) unless @value =~ /^[A-Z]{2}$/
    raise TypeError.new('Country sid is not supported') if defined?(Country) && !Country[@value]
  end

  def db_schema
    [:string, { limit: 2 }]
  end
end
