module TimeOptions
  def short use_default=false
    # lang = Lux.current.request.env['HTTP_ACCEPT_LANGUAGE'] rescue 'en'
    default = '%Y-%m-%d'
    fmt     = Lux.current.var.date_format.or(Lux.config.date_format || default)
    fmt     = default if use_default

    strftime fmt.sub('yyyy', '%Y').sub('mm', '%m').sub('dd', '%d')
  end

  def long use_default=false
    strftime("#{short(use_default)} %H:%M")
  end
end

class Time
  include TimeOptions

  class << self
    # Precise ago
    # Time.agop(61)   -> 1min 1sec
    # Time.agop(1111) -> 18min 31sec
    def agop secs, desc=nil
      return '-' unless secs

      [[60, :sec], [60, :min], [24, :hrs], [356, :days], [1000, :years]].map do |count, name|
        if secs > 0
          secs, n = secs.divmod(count)
          "#{n.to_i}#{name}"
        end
      end.compact.reverse.slice(0,2).join(' ')
    end

    # How long ago?
    def ago start_time, end_time=nil
      TimeDifference.new(start_time, end_time).humanize
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Generates a Time object from the given value.
    # Used by #expires and #last_modified.
    # extracted from Sinatra
    def for value
      if value.is_a? Numeric
        Time.at value
      elsif value.respond_to? :to_s
        Time.parse value.to_s
      else
        value.to_time
      end
    rescue Exception
      raise ArgumentError, "unable to convert #{value.inspect} to a Time object"
    end
  end
end

class DateTime
  include TimeOptions
end

class Date
  include TimeOptions
end

