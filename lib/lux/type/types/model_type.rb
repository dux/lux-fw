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

    # Keep only the fields the client sent, now type-coerced - but only when a
    # real model backs the field. There the absent keys are stored columns and
    # injecting them would clobber the row on a partial update. An ad-hoc nested
    # schema has no row behind it, so its declared defaults are meant to
    # materialise rather than be stripped back out.
    @value.select! { |k, _| given.include?(k.to_s) } if model_backed

    raise TypeError.new errors.to_json if errors.keys.first
  end

  def db_schema
    [:jsonb, {
      null: false
    }]
  end
end
