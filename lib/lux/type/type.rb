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

    class << self
      def load name
        klass = 'Lux::Type::%sType' % name.to_s.gsub(/[^\w]/, '').classify

        if const_defined? klass
          klass.constantize
        else
          raise ArgumentError, 'Lux type "%s" is not defined (%s)' % [name, klass]
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

      def allowed_opt? name
        return true if OPTS_KEYS.include?(name)

        OPTS[self] ||= {}
        return true if OPTS[self][name]

        msg  = %[Unallowed param "#{name}" for type "#{to_s}" found. Allowed are "#{OPTS_KEYS.join(', ')}"]
        msg += %[ + "#{OPTS[self].keys.join(', ')}"] if OPTS[self].keys.first

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
      out[1][:default] ||= opts[:default] unless opts[:default].nil?
      out[1][:null]      = false if !opts[:array] && opts[:required]
      out
    end

    # value suitable for DB storage, override in types that need special wrapping
    def db_value
      get
    end

    # coerce without validation - swallows TypeError from constraint checks
    def coerce_value
      return nil if value.nil?
      begin
        coerce
      rescue TypeError
      end
      value
    end

    def input_value
      value
    end
    alias :to_s :input_value

    private

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
