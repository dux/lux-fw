class Integer
  def pluralize(desc)
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
end
