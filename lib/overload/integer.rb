class Integer
  def pluralize desc
    if self == 0
      "no #{desc.to_s.pluralize}"
    elsif self == 1
      "#{self} #{desc}"
    else
      "#{self.dotted} #{desc.to_s.pluralize}"
    end
  end

  def dotted
    self.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse
  end

  def ordinalize
    abs_num = self.abs
    mod100 = abs_num % 100
    suffix = if mod100 >= 11 && mod100 <= 13
      'th'
    else
      case abs_num % 10
      when 1 then 'st'
      when 2 then 'nd'
      when 3 then 'rd'
      else 'th'
      end
    end
    "#{self}#{suffix}"
  end
  alias :to_ordinal :ordinalize

  def to_filesize
    base = 1024
    out = lambda do
      {
        'B'  => base,
        'KB' => base * base,
        'MB' => base * base * base,
        'GB' => base * base * base * base,
        'TB' => base * base * base * base * base
      }.each_pair { |e, s| return "#{(self.to_f / (s / base)).round(1)} #{e}" if self < s }
    end.call

    out.sub('.0 B', ' B')
  end
end
