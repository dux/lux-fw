class TimeDifference
  TIMES ||= [
    [:year,   60 * 60 * 24 * 365],
    [:month,  60 * 60 * 24 * 30],
    [:day,    60 * 60 * 24],
    [:hour,   60 * 60],
    [:minute, 60]
  ]

  LOCALE ||= {
    en: {
      in: 'in',
      before: 'before',
      in_few_econds: 'in few seconds',
      just_happend: 'just happend'
    },
    hr: {
      in: 'za',
      before: 'prije',
      in_few_econds: 'za par sekundi',
      just_happend: 'upravo sada'
    }
  }

  def initialize start_date, end_date=nil
    unless end_date
      @end_date   = start_date
      @start_date = Time.now
    end
  end

  def humanize
    diff = (@start_date.to_i - @end_date.to_i).abs

    TIMES.each do |(key, ref)|
      value = diff / ref
      return part(key, value) if value > 0
    end

    @start_date < @end_date ? locale(:in_few_econds) : locale(:just_happend)
  end

  def set_locale key, value
    raise ArgumentError.new('Key not found') unless locale(key)

    LOCALE[key] = value
  end

  private

  def part key, value
    kind = @start_date < @end_date ? locale(:in) : locale(:before)
    text = [value, value > 1 ? '%ss' % key : key].join(' ')
    [kind, text].join(' ')
  end

  def locale name
    LOCALE[:en][name]
  end
end
