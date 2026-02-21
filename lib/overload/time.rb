module TimeOptions
  def short use_default = false
    # lang = Lux.current.request.env['HTTP_ACCEPT_LANGUAGE'] rescue 'en'
    default_format = '%Y-%m-%d'
    date_format    = Lux.current.var[:date_format].or(Lux.config[:date_format] || default_format)
    date_format    = default_format if use_default
    date_format    = date_format.sub('yyyy', '%Y').sub('mm', '%m').sub('dd', '%d')

    current.strftime date_format
  end

  def long use_default=false
    current.strftime("#{short(use_default)} %H:%M")
  end

  def current
    if respond_to?(:utc) && time_zone = Lux.current.var[:time_zone]
      begin
        tz = TZInfo::Timezone.get(time_zone)
        tz.utc_to_local utc
      rescue TZInfo::InvalidTimezoneIdentifier => e
        Lux.logger.error '%s (%s)' % [e.message, time_zone]
        self
      end
    else
      self
    end
  end
end

class Time
  include TimeOptions

  class << self
    # prints proc speed of execution
    # it will print first execution separate from the rest, used in cache testing
    def speed num = 1
      start = Time.now
      yield
      total = Time.now - start
      puts 'Speed: %s sec for 1st run' % total.round(3)
      if num > 1
        start = Time.now
        (num - 1).times { yield }
        total = Time.now - start
        puts 'Other %s runs speed: %s sec, avg -> %s' % [num, total.round(3), (total/num).round(3)]
      end
    end

    # Precise ago
    # Time.agop(61)   -> 1min 1sec
    # Time.agop(1111) -> 18min 31sec
    def agop secs, desc = nil
      return '-' unless secs

      [[60, :sec], [60, :min], [24, :hrs], [356, :days], [1000, :years]].map do |count, name|
        if secs > 0
          secs, n = secs.divmod(count)
          "#{n.to_i}#{name}"
        end
      end.compact.reverse.slice(0,2).join(' ')
    end

    # How long ago?
    def ago start_time, end_time = nil
      start = Time.parse start_time.to_s if [String, Date].include?(start_time.class)
      TimeDifference.new(start || start_time, end_time, start_time.class).humanize
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

  def to_i
    Time.parse(to_s).to_i
  end
end

