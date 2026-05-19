class Lux::Type::HashType < Lux::Type
  error :en, :not_hash_type_error, 'value is not hash type'

  def coerce
    if value.is_a?(String) && value[0, 1] == '{'
      @value = JSON.parse(value)
    end

    @value ||= {}
    @value.delete_if { |_, v| v.respond_to?(:empty?) && v.empty? }

    error_for(:not_hash_type_error) unless @value.respond_to?(:keys) && @value.respond_to?(:values)

    if opts[:allow]
      for key in @value.keys
        @value.delete(key) unless opts[:allow].include?(key)
      end
    end
  end

  def default
    {}
  end

  def db_schema
    [:jsonb, {
      null: false,
      default: '{}'
    }]
  end
end
