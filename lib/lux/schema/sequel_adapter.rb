# Sequel integration for Lux::Schema. Activate per-model with:
#   Sequel::Model.plugin :lux_schema

module Sequel::Plugins::LuxSchema
  # audit columns are populated by the before_save filters
  # (plugins/db/plugins/before_save_filters.rb), never by the client, so
  # api_schema drops them. This is the single home for the list.
  AUDIT_COLUMNS = %i[created_at updated_at creator_ref updater_ref].freeze

  module ClassMethods
    def schema name = nil, &block
      name ||= self
      name = name.to_s.underscore.singularize
      value = Lux.schema name, type: :model, &block

      # let nested model validation resolve back to this model (-> api_schema)
      value.model_klass = self

      # Replay enum declarations captured by the `enum` DSL keyword onto
      # this Sequel model. The collection_ref hash lets the meta[:collection]
      # proc resolve Klass.<plural> at render time without us hard-coding
      # the class name at schema-define time.
      klass = self
      value.enums.each do |e|
        e[:collection_ref][:klass] = klass if e[:collection_ref]
        enum_opts = {
          field:    e[:field],
          method:   e[:method],
          values:   e[:values],
          helpers:  e[:helpers],
          validate: e[:validate]
        }
        # forward default only when meaningful: a declared default wins,
        # optional (`enum :foo?`) enums read blank as blank, required ones
        # keep the first-key fallback
        if !e[:default].nil?
          enum_opts[:default] = e[:default]
        elsif e[:required] == false
          enum_opts[:default] = nil
        end
        klass.enum e[:name], **enum_opts
      end

      if ENV['DB_MIGRATE'] == 'true' && defined?(AutoMigrate)
        AutoMigrate.apply_schema self
      end

      value
    end

    # API-facing schema: the model schema without framework-managed audit
    # columns. Override in an app model to exclude more (e.g.
    # `super.except(:internal_field)`).
    def api_schema
      (Lux.schema?(self) || schema).except(*AUDIT_COLUMNS)
    end
  end

  module InstanceMethods
    # returns Schema::Accessor or field rules hash
    # mp.schema                -> Lux::Schema::Accessor
    # mp.schema(:name)         -> { type: :string, required: true }
    def schema field = nil
      accessor = Lux::Schema::Accessor.new(self)
      field ? accessor.rules(field) : accessor
    end

    # calling validate on any object will validate all fields against the schema
    def validate
      super

      if schema = Lux.schema?(self.class)
        schema.validate(self) do |name, err|
          errors.add(name, err) unless (errors.on(name) || []).include?(err)
        end

        # this are rules unique to database, so we check them here
        pk_col = respond_to?(:ref) ? :ref : :id
        pk_val = self[pk_col]

        schema.rules.each do |field, rule|
          # check uniqe fields
          if unique = rule.dig(:meta, :unique)
            value = self[field]

            # we only check if field is changed
            if value.present? && column_changed?(field) && self.class.xwhere("LOWER(%s)=LOWER(?) and #{pk_col}::text<>?" % [field], value, pk_val.to_s).first
              error = unique.class == TrueClass ? %[Value "#{value}" for field "#{field}" has been already used, please chose another value.] : unique
              errors.add(field, error) unless (errors.on(field) || []).include?(error)
            end
          end

          # check protected fields
          if (prot = rule.dig(:meta, :protected)) && pk_val
            if column_changed?(field)
              error = prot.class == TrueClass ? "value once defined can't be overwritten." : prot
              errors.add(field, error) unless (errors.on(field) || []).include?(error)
            end
          end
        end
      end
    end
  end

  module DatasetMethods
  end
end
