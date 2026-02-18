class TimeDifference
  TIMES ||= [
    [:year,   60 * 60 * 24 * 365],
    [:month,  60 * 60 * 24 * 30],
    [:day,    60 * 60 * 24],
    [:hour,   60 * 60],
    [:minute, 60]
  ]

  LOCALE ||= {
    today: {
      en: 'today',
      hr: 'danas'
    },
    in: {
      en: 'in',
      hr: 'za'
    },
    before: {
      en: 'before',
      hr: 'prije'
    },
    in_few_seconds: {
      en: 'in few seconds',
      hr: 'za par sekundi'
    },
    just_happened: {
      en: 'just happened',
      hr: 'upravo sada'
    }
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
    diff = (@start_date.to_i - @end_date.to_i).abs

    if @klass == Date && diff < TIMES[2][1]
      return locale(:today)
      # @start_date < @end_date ? locale(:in_few_seconds) : locale(:just_happened)
    end

    TIMES.each do |(key, ref)|
      value = diff / ref
      return part(key, value) if value > 0
    end

    @start_date < @end_date ? locale(:in_few_seconds) : locale(:just_happened)
  end

  # def set_locale key, value
  #   raise ArgumentError.new('Key not found') unless locale(key)

  #   LOCALE[key] = value
  # end

  private

  def part key, value
    kind = @start_date < @end_date ? locale(:in) : locale(:before)
    text = [value, value > 1 ? '%ss' % key : key].join(' ')
    [kind, text].join(' ')
  end

  def locale name
    LOCALE[name][:en]
  end
end
