class Float
  # Convert float to currenct
  # `@sum.as_currency(pretty: false, strip: true, symbol: '$')`
  def as_currency opts={}
    opts = { symbol: opts } unless opts.is_a?(Hash)

    out = '%.2f' % self
    out = out.sub('.', ',')
    out = out.sub(/(\d)(\d{3}),/, '\1.\2,')
    out = out.sub(/(\d)(\d{3})\./, '\1.\2.')

    # remove decimal places
    out = out.split(',').first if opts[:strip]

    if opts[:pretty]
      out = out.sub(/^([\d\.]+),(\d{2})$/, '<span class="pretty-price"><b>\1</b><small>,\2</small></span> ')
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

  def dotted round_to=2
    main, suffix = sprintf("%.#{round_to}f", self).to_s.split('.').map(&:to_i)
    [main.dotted, suffix].join(',')
  end
end
