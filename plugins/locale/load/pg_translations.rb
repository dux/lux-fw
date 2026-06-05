# Sequel plugin for PostgreSQL JSONB translations. Ships with the locale
# plugin (it resolves through Lux.locale.current / Lux.locale.default).
# Apply per-model:  plugin :pg_translations
#
# Any column ending with _t is a translated JSONB field.
#   name_t  -> raw jsonb hash, eg: { "en" => "Hello", "hr" => "Bok" }
#   name    -> localized value for Lux.locale.current, fallback to Lux.locale.default

module Sequel::Plugins::PgTranslations
  module ClassMethods
    # Lazily detect _t columns from the database schema
    def t_columns
      @t_columns ||= db_schema.keys.select { |c| c.to_s.end_with?('_t') }
    end
  end

  module InstanceMethods
    private

    def _localized_value(t_col)
      data = self[t_col]
      return unless data.respond_to?(:key?)

      value = data[Lux.locale.current.to_s]
      return value if value.present?

      data[Lux.locale.default.to_s]
    end

    public

    def method_missing(name, *args, &block)
      t_col = :"#{name}_t"

      if args.empty? && !block && self.class.t_columns.include?(t_col)
        # Define real method on class to skip method_missing on subsequent calls
        self.class.class_eval do
          define_method(name) { _localized_value(t_col) }
        end
        _localized_value(t_col)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      self.class.t_columns.include?(:"#{name}_t") || super
    end
  end
end
