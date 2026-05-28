class Sequel::Model
  module ClassMethods
    # enum :priority, default: 2 do |f|
    #   f[3] = 'High'
    #   f[2] = { name: 'Normal', desc: '...' }.h
    # end
    # enum :kind, ['string', 'boolean', 'textarea']
    #
    # Generates:
    #   ClassName.priorities          -> values hash
    #   ClassName.priorities(2)       -> single value
    #   ClassName.priorities.for_select -> [[key, label], ...]
    #   instance#priority             -> label for stored key
    #
    # opts:
    #   field:    backing column (default: "#{method}_id" for Integer keys, else "#{method}_sid")
    #   method:   instance label method (default: name)
    #   default:  default key
    #   helpers:  :both (default), :class, :instance, false
    #   validate: false to skip save-time validation
    def enum name, opts={}, &block
      singular = name.to_s.singularize
      if singular != name.to_s && singular != name.to_s.pluralize
        Lux.shell.die 'enum :%s: name must be singular (did you mean :%s?)' % [name, singular]
      end

      # remember where the enum was declared so errors can point at the schema
      decl_loc = caller_locations(1, 1).first
      decl_at  = '%s:%d' % [decl_loc.path, decl_loc.lineno]

      if opts.is_a?(Array)
        opts = { values: opts, helpers: :class }
      end

      # plain Hash for the block form (not to_lux_hash) so Integer keys survive
      # for column-suffix detection; the caster below re-keys values anyway.
      raw_values = opts[:values] || {}.tap { |h| block.call(h) }

      opts[:method]  ||= name.to_s
      opts[:helpers]   = :both unless opts.key?(:helpers)
      # suffix follows the key type, matching schema_define.rb:
      # Integer keys -> _id (integer column), else _sid (string column)
      enum_keys      = raw_values.is_a?(Hash) ? raw_values.keys : raw_values.to_a
      opts[:field]   ||= opts[:method].to_s + (enum_keys.first.is_a?(Integer) ? '_id' : '_sid')

      class_method_name = name.to_s.pluralize.to_sym

      field_sym = opts[:field].to_sym
      col_type  = db_schema.dig(field_sym, :type)

      caster =
        case col_type
        when :integer then ->(k) { k.is_a?(Integer) ? k : Integer(k.to_s) rescue k }
        else               ->(k) { k.to_s }
        end

      values = raw_values.inject({}.to_lux_hash) { |h, (k,v)| h[caster.call(k)] = v; h }

      # Default falls back to the first declared key, so a blank column
      # transparently reads as the first enum value (Array, Hash, and
      # block-builder shapes all behave the same).
      opts[:default] = caster.call(opts[:default]) if opts[:default]
      opts[:default] ||= values.keys.first

      values.define_singleton_method(:for_select) do
        map { |k, v| [k, v.is_a?(Hash) ? v[:name] : v] }
      end

      do_instance = [:both, :instance].include?(opts[:helpers])
      do_class    = [:both, :class].include?(opts[:helpers])

      # Skip column-bound helpers when the column doesn't exist yet
      # (typical on a fresh DB during db:am - the model loads before
      # AutoMigrate creates the table). Class helpers + validation
      # below still install; once the table exists and the model is
      # reloaded, instance helpers attach normally.
      if do_instance && db_schema[field_sym]
        # Override the column reader so a blank stored value transparently
        # reads back as the default key (the first declared key, unless
        # `default:` was passed explicitly).
        default_key = opts[:default]
        define_method(field_sym) do
          val = self[field_sym]
          val.present? ? val : default_key
        end

        klass_name = self.name
        define_method(opts[:method]) do
          value = send(field_sym)
          return unless value.present?
          out = values[caster.call(value)]
          if !out && opts[:validate] != false
            raise 'enum %s.%s: key %s not found in %s (declared at %s)' %
              [klass_name, name, value.inspect, values.keys.inspect, decl_at]
          end
          out || value
        end
      elsif do_instance
        Lux.shell.info 'enum: field "%s" not found for "%s" on %s, skipping instance helpers' % [opts[:field], name, self.name]
      end

      if do_class
        define_singleton_method(class_method_name) do |id=nil|
          id ? values[caster.call(id)] : values
        end
      end

      if opts[:validate] != false && db_schema[field_sym]
        list = (instance_variable_get(:@_enums) || instance_variable_set(:@_enums, []))
        list << { field: field_sym, values: values, caster: caster, name: name }

        unless instance_variable_get(:@_enums_validation_installed)
          instance_variable_set(:@_enums_validation_installed, true)
          prepend(Module.new do
            define_method(:validate) do
              super()
              self.class.instance_variable_get(:@_enums)&.each do |e|
                val = self[e[:field]]
                next if val.nil?
                unless e[:values].key?(e[:caster].call(val))
                  errors.add(e[:field], "is not in #{e[:name]}: #{e[:values].keys.inspect}")
                end
              end
            end
          end)
        end
      end
    end
  end
end
