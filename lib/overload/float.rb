class Float

  def as_currency symbol=nil
    out = '%.2f' % self
    out = out.sub('.', ',')
    out = out.sub(/(\d)(\d{3}),/, '\1.\2,')
    out = out.sub(/(\d)(\d{3})\./, '\1.\2.')

    if symbol
      if symbol == '$'
        out = '%s%s' % [symbol, out]
      else
        out += " #{symbol}"
      end
    end

    out
  end

end