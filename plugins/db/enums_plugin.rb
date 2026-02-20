class Sequel::Model
  module ClassMethods
    # enums name: :steps, method: :step, field: :step_sid, default: 'o' do |list|
    #   list['o'] = 'Open'
    #   list['w'] = { name: 'Waiting', desc: '...' }.h
    # end
    # enums :steps
    #   list['o'] = 'Otvoreno'
    #   list['w'] = { name: 'Waiting', desc: '...' }.h
    # end
    # enums :steps, values: { 'o'=>'Open', 'w'=>'Waiting' }
    # enums :kinds, ['string', 'boolean', 'textarea']
    def enums name, opts={}, &block
      if opts.class == Array
        opts = {
          values: opts,
          field: false
        }
      end

      opts[:default] ||= opts[:values].first if opts[:values].class == Array

      values = opts[:values] || {}.to_hwia.tap { |_| block.call(_) }
      values = values.inject({}.to_hwia) { |h, (k,v)| h[k.to_s] = v; h }

      opts[:method]  ||= name.to_s.singularize
      opts[:default]   = values.keys.first unless opts.key?(:default)
      opts[:default]   = opts[:default].to_s

      unless opts[:field].class == FalseClass
        unless opts[:field]
          opts[:field] = opts[:method].to_s + '_sid'
          opts[:field] = opts[:method].to_s + '_id' unless db_schema[opts[:field].to_sym]
        end

        unless db_schema[opts[:field].to_sym]
          Lux.info 'Field %s or %s not found for enums %s' % [opts[:field].to_s.sub('_id', '_sid'), opts[:field], name]
        end

        define_method(opts[:field]) do
          self[opts[:field].to_sym].or opts[:default]
        end

        define_method(opts[:method]) do
          value = send(opts[:field])
          return unless value.present?

          out = values[value.to_s]
          raise('Key "%s" not found' % value) if !out && opts[:validate] != false
          out || value
        end
      end

      # this is class method that will list all options
      define_singleton_method(name) do |id=nil|
        id ? values[id] : values
      end
    end
  end
end

