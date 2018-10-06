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

      opts[:method]  ||= name.to_s.singularize
      opts[:default] ||= values.keys.first unless opts.key?(:default)

      unless opts[:field].class == FalseClass
        unless opts[:field]
          opts[:field] = opts[:method] + '_id'
          opts[:field] = opts[:method] + '_sid' unless db_schema[opts[:field].to_sym]
        end

        raise NameError.new('Field %s not found for enums %s' % [opts[:field], name]) unless db_schema[opts[:field].to_sym]

        define_method(opts[:method]) do
          value = send(opts[:field]).or opts[:default]
          return unless value.present?
          values[value] || raise('Key "%s" not found' % value)
        end
      end

      # this is class method that will list all options
      define_singleton_method(name) do |id=nil|
        id ? values[id] : values
      end
    end
  end
end

