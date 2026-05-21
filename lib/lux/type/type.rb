# Base type class. Subclasses live in lib/lux/type/types/ and are looked up by
# Lux::Type.load(:string) -> Lux::Type::StringType.

module Lux
  class Type
    ERRORS ||= {
      en: {
        min_length_error: 'min length is %s, you have %s',
        max_length_error: 'max length is %s, you have %s',
        min_value_error:  'min is %s, got %s',
        max_value_error:  'max is %s, got %s',
        unallowed_characters_error: 'is having unallowed characters',
        not_in_range: 'Value is not in allowed range (%s)'
      }
    }

    # default shared allowed opts keys
    OPTS      ||= {}
    OPTS_KEYS ||= [
      :allow,
      :allowed,
      :array,
      :default,
      :description,
      :delimiter,
      :duplicates,
      :index,
      :max,
      :max_count,
      :meta,
      :min,
      :min_count,
      :model,
      :name,
      :req,
      :required,
      :type,
      :values
    ]

    attr_reader :opts

    LOAD_CACHE ||= {}

    class << self
      def load name
        LOAD_CACHE[name] ||= begin
          klass = 'Lux::Type::%sType' % name.to_s.gsub(/[^\w]/, '').classify

          if const_defined? klass
            klass.constantize
          else
            raise ArgumentError, 'Lux type "%s" is not defined (%s)' % [name, klass]
          end
        end
      end

      def error locale, key, message
        locale = locale.to_sym
        ERRORS[locale] ||= {}
        ERRORS[locale][key.to_sym] = message
      end

      def opts key, desc
        OPTS[self] ||= {}
        OPTS[self][key] = desc
      end

      # walks ancestors so a subclass inherits its parent's declared opts
      def allowed_opt? name
        return true if OPTS_KEYS.include?(name)

        klass = self
        while klass.respond_to?(:opts) && klass <= Lux::Type
          return true if OPTS[klass] && OPTS[klass][name]
          klass = klass.superclass
        end

        own_keys = (OPTS[self] || {}).keys
        msg  = %[Unallowed param "#{name}" for type "#{to_s}" found. Allowed are "#{OPTS_KEYS.join(', ')}"]
        msg += %[ + "#{own_keys.join(', ')}"] if own_keys.first

        block_given? ? yield(msg) : raise(ArgumentError, msg)

        false
      end

      def db_schema
        new(nil).db_schema
      end
    end

    def initialize value, opts = {}, &block
      value = value.strip if value.is_a?(String)

      opts.keys.each { |key| self.class.allowed_opt?(key) }

      @value = value
      @opts  = opts
      @block = block
    end

    # raw value, one should use get
    def value &block
      if block_given?
        @value = block.call @value
      else
        @value
      end
    end

    def get
      if value.nil?
        opts[:default].nil? ? default : opts[:default]
      else
        coerce

        if opts[:values] && !opts[:values].map(&:to_s).include?(@value.to_s)
          error_for(:not_in_range, opts[:values].join(', '))
        end

        input_value
      end
    end

    def coerce
    end
    alias :set :coerce

    def default
      nil
    end

    def db_field
      out = db_schema
      out[1] ||= {}
      # type's own db_schema default wins; user-supplied :default fills it in only when type left it blank
      out[1][:default] ||= opts[:default] unless opts[:default].nil?
      out[1][:null]      = false if !opts[:array] && opts[:required]
      out
    end

    # value suitable for DB storage, override in types that need special wrapping
    def db_value
      get
    end

    # coerce without validation - swallows any parse/constraint failure
    def coerce_value
      return nil if value.nil?
      begin
        coerce
      rescue StandardError
      end
      value
    end

    def input_value
      value
    end

    def to_s
      input_value.to_s
    end

    private

    # shared comparable check for numeric types (Integer, Float, Date, ...)
    def check_min_max
      error_for(:min_value_error, opts[:min], value) if opts[:min] && value < opts[:min]
      error_for(:max_value_error, opts[:max], value) if opts[:max] && value > opts[:max]
    end

    # shared length check for string-shaped types (String, Email, Slug, ...)
    def check_min_max_length max_default = nil, min_default = nil
      min = opts[:min] || min_default
      max = opts[:max] || max_default
      error_for(:min_length_error, min, value.length) if min && value.length < min
      error_for(:max_length_error, max, value.length) if max && value.length > max
    end

    def error_for name, *args
      locale =
        if Lux.respond_to?(:current) && Lux.current
          Lux.current.locale.to_s rescue nil
        elsif defined?(I18n)
          I18n.locale
        end

      locale  = :en if locale.to_s == ''
      pointer = ERRORS[locale.to_sym] || ERRORS[:en]
      error   = @opts.dig(:meta, locale, name) || @opts.dig(:meta, name) || pointer[name]
      error   = error % args if args.first

      raise 'Type error :%s not defined' % name unless error
      raise TypeError.new(error)
    end
  end
end
