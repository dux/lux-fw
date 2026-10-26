class Lux::Type::CountryType < Lux::Type
  error :en, :country_length_error, 'must be exactly 2 characters'

  def coerce
    @value = @value.to_s.upcase
    error_for(:country_length_error) unless @value.length == 2
    error_for(:unallowed_characters_error) unless @value.match?(/\A[A-Z]{2}\z/)
  end

  def db_schema
    [:string, { limit: 2 }]
  end
end
