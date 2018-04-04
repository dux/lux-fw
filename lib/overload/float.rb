class Float

  def as_currency
    out = '%.2f' % self
    out = out.sub('.', ',')
    out = out.sub(/(\d)(\d{3})/, '\1.\2')
    out
  end

end