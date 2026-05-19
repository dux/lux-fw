# Provides hash-like access to typed field values on a model instance.
#
# Usage:
#   mp = MapPoint.last
#   mp.schema[:location].db_value  # => Sequel.pg_array([44.39, 8.96], :float)
#   mp.schema[:location].get       # => [44.39, 8.96]
#   mp.schema[:location].to_s      # => "44.391598, 8.960724"

module Lux
  class Schema
    class Accessor
      def initialize object
        @object = object
        @schema = Lux.schema?(object.class)
      end

      def [] field
        field = field.to_sym
        return nil unless @schema

        opts = @schema.rules[field]
        return nil unless opts

        value = @object[field]
        Lux::Type.load(opts[:type]).new(value, opts)
      end

      # return coerced value for a field
      def get field
        self[field]&.db_value
      end

      # coerce incoming value and store on model (no validation)
      def set field, value
        field = field.to_sym
        return @object[field] = value unless @schema

        opts = @schema.rules[field]
        return @object[field] = value unless opts

        type = Lux::Type.load(opts[:type]).new(value, opts)
        @object[field] = type.coerce_value
      end

      # validate field(s) - raises TypeError or yields error messages
      # schema.validate(:email)                    - validate single field, raise on error
      # schema.validate(:email) { |err| ... }      - validate single field, yield error
      # schema.validate                            - validate all fields, raise first error
      # schema.validate { |field, err| ... }       - validate all fields, yield each error
      def validate field = nil, &block
        raise ArgumentError, "No schema found" unless @schema

        if field
          validate_field field.to_sym, &block
        else
          validate_all(&block)
        end
      end

      # return schema rules for a field or all fields
      def rules field = nil
        return nil unless @schema
        field ? @schema.rules[field.to_sym] : @schema.rules
      end

      def keys
        @schema ? @schema.rules.keys : []
      end

      def each &block
        keys.each { |k| yield k, self[k] }
      end

      private

      def validate_field field, &block
        opts = @schema.rules[field]
        raise ArgumentError, "Field :#{field} not in schema" unless opts

        value = @object[field]
        type = Lux::Type.load(opts[:type]).new(value, opts)

        begin
          type.get
          nil
        rescue TypeError => e
          block ? yield(e.message) : raise
        end
      end

      def validate_all &block
        errors = @schema.validate(@object)
        return nil if errors.empty?

        if block
          errors.each { |field, msg| yield(field, msg) }
        else
          field, msg = errors.first
          raise TypeError, msg
        end
      end
    end
  end
end
