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

      opts[:default] ||= opts.first if opts[:values].class == Array

      values = opts[:values] || {}.tap { |_| block.call(_) }
      values = values.inject({}) { |h, (k,v)| h[k.to_s] = v; h }

      opts[:method]  ||= name.to_s.singularize
      opts[:default]   = values.keys.first unless opts.key?(:default)
      opts[:default]   = opts[:default].to_s

      unless opts[:field].class == FalseClass
        unless opts[:field]
          opts[:field] = opts[:method] + '_id'
          opts[:field] = opts[:method] + '_sid' unless db_schema[opts[:field].to_sym]
        end

        raise NameError.new('Field %s or %s not found for enums %s' % [opts[:field].sub('_sid', '_id'), opts[:field], name]) unless db_schema[opts[:field].to_sym]

        define_method(opts[:field]) do
          self[opts[:field].to_sym].or opts[:default]
        end

        define_method(opts[:method]) do
          value = send(opts[:field])
          return unless value.present?
          values[value.to_s] || raise('Key "%s" not found' % value)
        end
      end

      # this is class method that will list all options
      define_singleton_method(name) do |id=nil|
        id ? values[id] : values
      end
    end
  end
end

