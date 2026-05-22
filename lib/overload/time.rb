require_relative '../lux/utils/time_options'

class Time
  include Lux::Utils::TimeOptions

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
      Lux::Utils::TimeDifference.new(start || start_time, end_time, start_time.class).humanize
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
  include Lux::Utils::TimeOptions
end

class Date
  include Lux::Utils::TimeOptions

  def to_i
    Time.parse(to_s).to_i
  end
end

