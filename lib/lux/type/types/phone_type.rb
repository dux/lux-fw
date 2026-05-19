class Lux::Type::PhoneType < Lux::Type
  error :en, :invalid_phone, 'is not a valid phone number'

  def coerce
    value do |data|
      data.to_s.gsub(/[\(\)\-]/, ' ').gsub(/\s+/, ' ').strip
    end

    error_for(:invalid_phone) unless value =~ /^[\d\s\+]+$/ && value.scan(/\d/).length >= 5
  end

  def db_schema
    [:string, { limit: 50 }]
  end
end
