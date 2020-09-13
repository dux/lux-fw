class Object
  LUX_AUTO_LOAD = {}

  def self.const_missing klass, path=nil
    klass = klass.to_s if klass.class == Symbol

    if path
      LUX_AUTO_LOAD[klass] = path
      return
    elsif LUX_AUTO_LOAD.keys.length == 0
      for file in `find ./app -type f -name *.rb`.split($/)
        klass_file = file.split('/').last.sub('.rb', '').classify
        LUX_AUTO_LOAD[klass_file] ||= file
      end
    end

    if @_last_autoload_class == klass
      error      = ['Can\'t find and autoload module/class: "%s"' % klass]
      call_file  = caller.find{ |f| !f.include?('lux-fw/') && !f.include?('/.') && !f.include?('`evaluate') }

      if call_file
        call_file  = call_file.sub(Dir.pwd, '.')
        err_folder = call_file.split(':').first.sub(/\/[^\/]+$/, '')
        file       = klass.underscore
        klass_path = [err_folder, '%s/lib' % err_folder]
                       .map   { |folder| '%s/%s.rb' % [folder, file] }
                       .find  { |file| File.exist?(file) }

        error.push ["Searched in #{err_folder}/#{file}.rb", "#{err_folder}/lib/#{file}.rb", "./app/**/#{file}.rb"].join(', ')
      end

      raise NameError, error.join(' ')
    else
      @_last_autoload_class = klass
    end

    klass_path ||= LUX_AUTO_LOAD[klass.to_s]

    require klass_path.sub('.rb', '') if klass_path

    # puts '* Autoload: %s from %s' % [klass, klass_path]

    Object.const_get(klass)
  end

  ###

  def or _or=nil, &block
    self.blank? || self == 0 ? (block ? block.call : _or) : self
  end

  def try *args, &block
    return nil if self.class == NilClass
    data = self.send(*args) || return
    block_given? ? block.call(data) : data
  end

  def die desc=nil, exp_object=nil
    desc ||= 'died without desc'
    desc = '%s: %s' % [exp_object.class, desc] if exp_object
    puts desc.red
    puts caller.slice(0, 10)
    raise desc
  end

  # this will capture plain Hash and Hash With Indifferent Access
  def is_hash?
    self.class.to_s.index('Hash') ? true : false
  end

  def is_array?
    self.class.to_s.index('Array') ? true : false
  end

  def is_string?
    self.class.to_s == 'String' ? true : false
  end

  def is_false?
    self.class.name == 'FalseClass' ? true : false
  end

  def is_true?
    self ? true :false
  end

  def is_numeric?
    Float(self) != nil rescue false
  end

  def is_symbol?
    self.class.to_s == 'Symbol' ? true : false
  end

  def is_boolean?
    self.class == TrueClass || self.class == FalseClass
  end

  def andand func=nil
    if present?
      if block_given?
        yield(self)
      else
        func ? send(func) : self
      end
    else
      block_given? || func ? nil : {}.to_hwia
    end
  end

  def instance_variables_hash
    vars = instance_variables - [:@current]
    vars = vars.reject { |var| var[0,2] == '@_' }
    Hash[vars.map { |name| [name, instance_variable_get(name)] }]
  end

  # value should be Float
  # value.is! Float
  def is! value
    if value == self.class
      true
    else
      raise ArgumentError.new('Expected %s but got %s in %s' % [value, self.class, caller[0]])
    end
  end

  # value can be nil but if defined should be Float
  # value.is? Float
  def is? value
    is! value
  end
end

