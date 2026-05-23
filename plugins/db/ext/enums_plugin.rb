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
    #   field:    backing column (default: "#{method}_sid")
    #   method:   instance label method (default: name)
    #   default:  default key
    #   helpers:  :both (default), :class, :instance, false
    #   validate: false to skip save-time validation
    def enum name, opts={}, &block
      if opts.is_a?(Array)
        opts = { values: opts, helpers: :class }
      end

      opts[:default] ||= opts[:values].first if opts[:values].is_a?(Array)

      raw_values = opts[:values] || {}.to_lux_hash.tap { |_| block.call(_) }

      opts[:method]  ||= name.to_s
      opts[:helpers]   = :both unless opts.key?(:helpers)
      opts[:field]   ||= opts[:method].to_s + '_sid'

      class_method_name = name.to_s.pluralize.to_sym

      field_sym = opts[:field].to_sym
      col_type  = db_schema.dig(field_sym, :type)

      caster =
        case col_type
        when :integer then ->(k) { k.is_a?(Integer) ? k : Integer(k.to_s) rescue k }
        else               ->(k) { k.to_s }
        end

      values = raw_values.inject({}.to_lux_hash) { |h, (k,v)| h[caster.call(k)] = v; h }
      opts[:default] = caster.call(opts[:default]) if opts[:default]

      values.define_singleton_method(:for_select) do
        map { |k, v| [k, v.is_a?(Hash) ? v[:name] : v] }
      end

      do_instance = [:both, :instance].include?(opts[:helpers])
      do_class    = [:both, :class].include?(opts[:helpers])

      if do_instance
        unless db_schema[field_sym]
          Lux.shell.die 'enum: field "%s" not found for "%s" on %s' % [opts[:field], name, self.name]
        end

        define_method(opts[:method]) do
          value = self[field_sym]
          return unless value.present?
          out = values[caster.call(value)]
          raise('Key "%s" not found' % value) if !out && opts[:validate] != false
          out || value
        end
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
