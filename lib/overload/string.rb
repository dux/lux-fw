class String
  # simple markdown
  def as_html
    self.gsub($/, '<br />')
  end

  # convert escaped strings, remove scritpts
  def to_html opts={}
    value = self.gsub(/&lt;/, '<').gsub(/&gt;/, '>').gsub(/&amp;/,'&')
    value = value.gsub(/<script/,'&lt;script') unless opts[:script]
    value = value.gsub(/<link/,'&lt;link') unless opts[:link]
    value
  end

  def trim(len)
    return self if self.length<len
    data = self.dup[0,len]+'&hellip;'
    data
  end

  def first
    self[0,1]
  end

  def sanitize
    Sanitize.clean(self, :elements=>%w[span ul ol li b bold i italic u underline hr br p], :attributes=>{'span'=>['style']} )
  end

  def wrap node_name, opts={}
    return self unless node_name
    opts.tag(node_name, self)
  end

  def fix_ut8
    self.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '?')
  end

  def parse_erb
    self.gsub(/<%=([^%]+)%>/) { eval $1; }
  end

  def parameterize
    self.downcase.gsub(/[^\w]+/,'-')
  end

  def to_url
    str_from = 'šđčćžŠĐČĆŽäÄéeöÖüüÜß'
    str_to   = 'sdcczSDCCZaAeeoOuuUs'
    str      = self.downcase.gsub(/\s+/,'-').tr(str_from, str_to)
    # self.downcase.gsub(/\s+/,'-').tr(str_from, str_to).gsub(/[^\w\-]/,'')
    str.sub(/\.$/, '').gsub('&',' and ').gsub('.',' dot ').parameterize.gsub('-dot-','.').downcase[0, 50].sub(/[\.\-]$/,'')
  end

  def css_to_hash
    self.split('&').inject({}) do |h,line|
      el = line.split('=', 2)
      h[el[0]] = el[1]
      h
    end
  end

  def to_a
    self.split(/\s*,\s*/)
  end

  def starts_with? prefix
    prefix.respond_to?(:to_str) && self[0, prefix.length] == prefix
  end

  def ends_with? suffix
    suffix.is_a?(String) && self[-suffix.length, suffix.length] == suffix && self != suffix
   end

  def last(num=1)
    len = self.length
    self[len-num, len]
  end

  def span_green
    %[<span style="color: #080;">#{self}</span>]
  end

  def span_red
    %[<span style="color: #800;">#{self}</span>]
  end

  # remomove colorize gem string colors
  def decolorize
    self.gsub(/\[0;\d\d;\d\dm([^\[]*)\[0m/) { $1 }
  end

  def escape
    CGI::escape self
  end

  def unescape
    CGI::unescape self
  end
end
