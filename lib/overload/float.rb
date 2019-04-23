class Float

  def as_currency opts={}
    opts = { symbol: opts } unless opts.is_a?(Hash)

    out = '%.2f' % self
    out = out.sub('.', ',')
    out = out.sub(/(\d)(\d{3}),/, '\1.\2,')
    out = out.sub(/(\d)(\d{3})\./, '\1.\2.')

    if opts[:pretty]
      out = out.sub(/^([\d\.]+),(\d{2})$/, '<b>\1</b><small>,\2</small> ')
    end

    if symbol = opts[:symbol]
      symbol = symbol.upcase

      if symbol == '$'
        out = '%s%s' % [symbol, out]
      else
        out += " #{symbol}"
      end
    end

    out
  end

end