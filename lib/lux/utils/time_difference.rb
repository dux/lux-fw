module Lux
module Utils
class TimeDifference
  TIMES ||= [
    [:year,   60 * 60 * 24 * 365],
    [:month,  60 * 60 * 24 * 30],
    [:day,    60 * 60 * 24],
    [:hour,   60 * 60],
    [:minute, 60]
  ]

  LOCALE ||= {
    today:          { en: 'today' },
    in:             { en: 'in' },
    before:         { en: 'before' },
    in_few_seconds: { en: 'in few seconds' },
    just_happened:  { en: 'just happened' }
  }

  def initialize start_date, end_date = nil, klass = nil
    if end_date
      @start_date = start_date
      @end_date   = end_date
    else
      @end_date   = start_date
      @start_date = Time.now
    end

    @klass = klass
  end

  def humanize
    @future = @start_date.to_i < @end_date.to_i
    diff = (@start_date.to_i - @end_date.to_i).abs

    if @klass == Date && diff < TIMES[2][1]
      return locale(:today)
      # @future ? locale(:in_few_seconds) : locale(:just_happened)
    end

    TIMES.each do |(key, ref)|
      value = diff / ref
      return part(key, value) if value > 0
    end

    @future ? locale(:in_few_seconds) : locale(:just_happened)
  end

  private

  def part key, value
    kind = @future ? locale(:in) : locale(:before)
    text = [value, value > 1 ? '%ss' % key : key].join(' ')
    [kind, text].join(' ')
  end

  def locale name
    LOCALE[name][:en]
  end
end
end
end
