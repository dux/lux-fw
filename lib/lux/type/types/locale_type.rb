class Lux::Type::LocaleType < Lux::Type
  error :en, :locale_bad_format, 'Locale "%s" is in bad format (should be xx or xx-xx)'

  def coerce
    value(&:to_s)
    error_for(:locale_bad_format, value) unless value =~ /\A[\w\-]{2,5}\z/
  end

  def db_schema
    [:string, { limit: 5 }]
  end
end
