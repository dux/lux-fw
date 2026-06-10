class Lux::Type::ModelType < Lux::Type
  def coerce
    value(&:to_h)

    errors = {}
    schema = opts[:model].is_a?(Lux::Schema) ? opts[:model] : Lux.schema(opts[:model])

    # When the field references a real model, validate against its api_schema
    # (audit columns excluded) and skip required: the values live on the row, so
    # partial/embedded input must not demand every column. Ad-hoc nested schemas
    # (no backing model) keep their declared required rules.
    model_backed = schema.model_klass.respond_to?(:api_schema)
    schema = schema.model_klass.api_schema if model_backed

    schema.validate value, strict: true, required: !model_backed do |field, error|
      errors[field] = error
    end

    @value.delete_if { |_, v| v.respond_to?(:empty?) && v.empty? }

    raise TypeError.new errors.to_json if errors.keys.first
  end

  def db_schema
    [:jsonb, {
      null: false
    }]
  end
end
