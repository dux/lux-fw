# Sequel integration for Lux::Schema. Activate per-model with:
#   Sequel::Model.plugin :lux_schema

module Sequel::Plugins::LuxSchema
  module ClassMethods
    def schema name = nil, &block
      name ||= self
      name = name.to_s.underscore.singularize
      value = Lux.schema name, type: :model, &block

      if ENV['DB_MIGRATE'] == 'true' && defined?(AutoMigrate)
        AutoMigrate.apply_schema self
      end

      value
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
        schema.rules.each do |field, rule|
          # check uniqe fields
          if unique = rule.dig(:meta, :unique)
            id    = self[:id] || 0
            value = self[field]

            # we only check if field is changed
            if value.present? && column_changed?(field) && self.class.xwhere("LOWER(%s)=LOWER(?) and #{respond_to?(:ref) ? :ref : :id}::text<>?" % [field], value, id.to_s).first
              error = unique.class == TrueClass ? %[Value "#{value}" for field "#{field}" has been already used, please chose another value.] : unique
              errors.add(field, error) unless (errors.on(field) || []).include?(error)
            end
          end

          # check protected fields
          if (prot = rule.dig(:meta, :protected)) && self[:id]
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
