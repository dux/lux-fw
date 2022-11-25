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

  def to_filesize
    out = lambda do
      {
        'B'  => 1024,
        'KB' => 1024 * 1024,
        'MB' => 1024 * 1024 * 1024,
        'GB' => 1024 * 1024 * 1024 * 1024,
        'TB' => 1024 * 1024 * 1024 * 1024 * 1024
      }.each_pair { |e, s| return "#{(self.to_f / (s / 1024)).round(1)} #{e}" if self < s }
    end.call

    out.sub('.0 B', ' B')
  end
end
