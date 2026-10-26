require_relative '../lux/utils/time_options'

class Time
  include Lux::Utils::TimeOptions

  class << self
    # Precise ago
    # Time.agop(61)   -> 1min 1sec
    # Time.agop(1111) -> 18min 31sec
    def agop secs
      return '-' unless secs

      [[60, :sec], [60, :min], [24, :hrs], [365, :days], [1000, :years]].map do |count, name|
        if secs > 0
          secs, n = secs.divmod(count)
          "#{n.to_i}#{name}"
        end
      end.compact.reverse.slice(0,2).join(' ')
    end

    # How long ago?
    def ago start_time, end_time = nil
      return unless start_time

      norm = ->(t) { t.is_a?(::String) || t.is_a?(::Date) ? Time.parse(t.to_s) : t }
      Lux::Utils::TimeDifference.new(norm.(start_time), end_time && norm.(end_time), start_time.class).humanize
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

class DateTime
  include Lux::Utils::TimeOptions
end

class Date
  include Lux::Utils::TimeOptions

  def to_i = to_time.to_i
end

