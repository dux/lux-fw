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

  FILESIZE_UNITS ||= %w[B KB MB GB TB PB EB]

  def to_filesize
    size, exp = to_f, 0
    while size.abs >= 1024 && exp < FILESIZE_UNITS.size - 1
      size /= 1024
      exp += 1
    end
    exp.zero? ? "#{self} B" : "#{size.round(1)} #{FILESIZE_UNITS[exp]}"
  end
end
