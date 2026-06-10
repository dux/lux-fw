class Lux::Type::ModelType < Lux::Type
  def coerce
    value(&:to_h)

    # remember what the client actually sent: schema params are partial input,
    # so only these keys get coerced and returned (Schema#validate would
    # otherwise inject every absent field as nil/default and clobber stored
    # columns on update)
    given  = @value.keys.map(&:to_s)
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

    # keep only the fields the client sent, now type-coerced
    @value.select! { |k, _| given.include?(k.to_s) }

    raise TypeError.new errors.to_json if errors.keys.first
  end

  def db_schema
    [:jsonb, {
      null: false
    }]
  end
end
