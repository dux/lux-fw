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
    def enums name, opts={}, &block
      if name.is_a?(Hash)
        opts = name
      else
        opts[:name] = name
      end

      values = opts[:values] || {}.tap { |_| block.call(_) }

      opts[:method]  ||= name.to_s.singularize
      opts[:default] ||= values.keys.first unless opts.key?(:default)

      unless opts[:field]
        opts[:field] = opts[:method] + '_id'
        opts[:field] = opts[:method] + '_sid' unless db_schema[opts[:field].to_sym]
      end

      raise NameError.new('Field %s not found for enums %s' % [opts[:field], opts[:name]]) unless db_schema[opts[:field].to_sym]

      # this is class method that will list all options
      define_singleton_method(opts[:name]) do
        values
      end

      define_method(opts[:method]) do
        key = self[opts[:field]] || opts[:default]
        return unless key.present?
        values[key] || raise('Key "%s" not found' % key)
      end
    end
  end
end

