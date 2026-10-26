class Float
  # Convert float to currenct
  # `@sum.as_currency(pretty: false, strip: true, symbol: '$')`
  def as_currency opts = {}
    opts = { symbol: opts } unless opts.is_a?(::Hash)
    main, dec = format('%.2f', self).split('.')
    main = main.gsub(/(\d)(?=(\d{3})+\z)/, '\\1.')
    out  = opts[:strip] ? main : "#{main},#{dec}"
    if opts[:pretty] && !opts[:strip]
      out = Lux::SafeString.join([main.tag(:b), ",#{dec}".tag(:small)]).tag(:span, class: 'pretty-price')
    end
    if symbol = opts[:symbol]&.to_s&.upcase
      out = symbol == '$' ? Lux::SafeString.join([symbol, out]) : Lux::SafeString.join([out, " #{symbol}"])
    end
    out
  end
end
