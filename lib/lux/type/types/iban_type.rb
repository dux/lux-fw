class Lux::Type::IbanType < Lux::Type
  error :en, :invalid_iban, 'is not a valid IBAN'

  def coerce
    value { |data| data.to_s.gsub(/\s/, '').upcase }
    error_for(:invalid_iban) unless valid?
  end

  def db_schema
    [:string, { limit: 34 }]
  end

  private

  def valid?
    return false unless @value =~ /^[A-Z]{2}[0-9]{2}[A-Z0-9]{4,30}$/
    rearranged = @value[4..] + @value[0..3]
    numeric = rearranged.chars.map { |c| c =~ /\d/ ? c : (c.ord - 55).to_s }.join
    numeric.to_i % 97 == 1
  end
end
