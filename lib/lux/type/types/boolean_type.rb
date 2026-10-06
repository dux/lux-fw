class Lux::Type::BooleanType < Lux::Type
  error :en, :unsupported_boolean, 'Unsupported boolean param value: %s'

  def coerce
    value do |_|
      bool = _.to_s
      next false if bool == ''

      parsed = Lux::Utils::Boolean.parse(bool)
      parsed.nil? ? error_for(:unsupported_boolean, bool) : parsed
    end
  end

  def db_schema
    [:boolean, {
      default: opts[:default] || false
    }]
  end
end
