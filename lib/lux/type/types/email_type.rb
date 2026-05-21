class Lux::Type::EmailType < Lux::Type
  opts :min, 'Minimum email length'
  opts :max, 'Maximum email length'

  error :en, :missing_monkey_error, 'is missing @'

  def coerce
    value do |email|
      email.downcase.gsub(/\s+/, '')
    end

    check_min_max_length 120, 5

    error_for(:missing_monkey_error) unless value.include?('@')
  end

  def db_schema
    [:string, {
      limit: opts[:max] || 120
    }]
  end
end
