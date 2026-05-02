class HtmlTable
  # t.default_order { |scope| scope.order(:name) }
  def default_order &block
    @default_order = block
  end

  # t.scope_filter { |scope| scope.where(active: true) }
  def scope_filter &block
    @scope_filter = block
  end

  # t.onclick { |object| "window.open('%s')" % object.dboard_path }
  def onclick &block
    @onclick = block
  end

  # t.search :q do |scope, value|
  #   scope.xlike(value, :name)
  # end
  def search qs, type=nil, opts={}, &block
    @searches.push [qs, type || :text, opts, block]
  end

  private

  def as_boolean col
    proc do |object|
      val = object.send(col[:field])
      val ? '&#10003;' : ''
    end
  end

  def as_date col
    proc do |object|
      val = object.send(col[:field])
      val.respond_to?(:strftime) ? val.strftime('%Y-%m-%d') : val.to_s
    end
  end

  def as_datetime col
    proc do |object|
      val = object.send(col[:field])
      val.respond_to?(:strftime) ? val.strftime('%Y-%m-%d %H:%M') : val.to_s
    end
  end

  def as_number col
    proc do |object|
      val = object.send(col[:field])
      val.respond_to?(:to_i) ? val.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse : val.to_s
    end
  end

  def as_currency col
    proc do |object|
      val = object.send(col[:field])
      val ? '%.2f' % val : ''
    end
  end

  def as_truncate col
    limit = col[:limit] || 50
    proc do |object|
      val = object.send(col[:field]).to_s
      val.length > limit ? val[0, limit] + '...' : val
    end
  end

  def as_link col
    proc do |object|
      val = object.send(col[:field])
      href = col[:href] ? col[:href].call(object) : val
      HtmlTag.a(href: href) { val.to_s }
    end
  end

  def as_image col
    proc do |object|
      val = object.send(col[:field])
      width = col[:width] || 40
      val ? HtmlTag.img(src: val, style: "width: #{width}px") : ''
    end
  end

  def as_percent col
    proc do |object|
      val = object.send(col[:field])
      val ? '%.1f%%' % (val * 100) : ''
    end
  end

  def as_email col
    proc do |object|
      val = object.send(col[:field])
      val ? HtmlTag.a(href: "mailto:#{val}") { val } : ''
    end
  end

  def as_list col
    proc do |object|
      val = object.send(col[:field])
      Array(val).join(', ')
    end
  end
end
