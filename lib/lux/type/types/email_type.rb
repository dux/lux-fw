class Lux::Type::EmailType < Lux::Type
  error :en, :not_8_chars_error, 'is not having at least 8 characters'
  error :en, :missing_monkey_error, 'is missing @'

  def coerce
    value do |email|
      email.downcase.gsub(/\s+/, '')
    end

    error_for(:not_8_chars_error) unless value.to_s.length > 7
    error_for(:missing_monkey_error) unless value.include?('@')
  end

  def db_schema
    [:string, {
      limit: @opts[:max] || 120
    }]
  end
end
