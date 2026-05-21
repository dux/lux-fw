class Lux::Type::HashType < Lux::Type
  error :en, :not_hash_type_error, 'value is not hash type'

  def coerce
    if value.is_a?(String) && value.strip[0, 1] == '{'
      begin
        @value = JSON.parse(value)
      rescue JSON::ParserError
        error_for(:not_hash_type_error)
      end
    end

    @value ||= {}

    error_for(:not_hash_type_error) unless @value.respond_to?(:keys) && @value.respond_to?(:values)

    # drop blank strings only - keep empty arrays/hashes that the caller put there on purpose
    @value.delete_if { |_, v| v.is_a?(String) && v.strip.empty? }

    if opts[:allow]
      @value.delete_if { |k, _| !opts[:allow].include?(k) }
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
