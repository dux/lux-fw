module TimeOptions
  def short
    strftime("%Y-%m-%d")
  end

  def long
    strftime("%Y-%m-%d %H:%M")
  end
end

class Time
  include TimeOptions

  class << self
    # humanize_seconds(61)   -> 1min 1sec
    # humanize_seconds(1111) -> 18min 31sec
    def humanize_seconds secs
      return '-' unless secs
      secs = secs.to_i
      [[60, :sec], [60, :min], [24, :hrs], [356, :days], [1000, :years]].map{ |count, name|
        if secs > 0
          secs, n = secs.divmod(count)
          "#{n.to_i}#{name}"
        end
      }.compact.reverse.slice(0,2).join(' ')
    end

    def ago start_time, end_time=nil
      start_time = Time.new(start_time.year, start_time.month, start_time.day) if start_time.class == Date

      end_time ||= Time.now
      time_diff = end_time.to_i - start_time.to_i

      in_past = time_diff > 0 ? true : false
      time_diff = time_diff.abs

      d_minutes = (time_diff / 60).round rescue 0
      d_hours   = (time_diff / (60 * 60)).round rescue 0
      d_days    = (time_diff / (60*60 * 24)).round rescue 0
      d_months  = (time_diff / (60*60*24 * 30)).round rescue 0
      d_years   = (time_diff / (60*60*24*30 * 12)).round rescue 0

      return (in_past ? 'few sec ago' : 'in few seconds') if time_diff < 10
      return (in_past ? 'less than min ago' : 'in less then a minute') if time_diff < 60

      template = in_past ? '%s ago' : 'in %s'

      return template % d_minutes.pluralize('min') if d_minutes < 60
      return template % d_hours.pluralize('hour') if d_hours < 24
      return template % d_days.pluralize('day') if d_days < 31
      return template % d_months.pluralize('month') if d_months < 12
      return template % d_years.pluralize('year')
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Generates a Time object from the given value.
    # Used by #expires and #last_modified.
    # extracted from Sinatra
    def for(value)
      if value.is_a? Numeric
        Time.at value
      elsif value.respond_to? :to_s
        Time.parse value.to_s
      else
        value.to_time
      end
    rescue ArgumentError => boom
      raise boom
    rescue Exception
      raise ArgumentError, "unable to convert #{value.inspect} to a Time object"
    end
  end
end

class DateTime
  include TimeOptions
end
