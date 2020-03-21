class String
  def constantize
    Object.const_get('::'+self)
  end

  # simple markdown
  def as_html
    self
      .gsub($/, '<br />')
      .gsub(/(https?:\/\/[^\s<]+)/) { %[<a href="#{$1}">#{$1}</a>] }
  end

  # convert escaped strings, remove scritpts
  def to_html opts={}
    value = self.gsub(/&lt;/, '<').gsub(/&gt;/, '>').gsub(/&amp;/,'&')
    value = value.gsub(/<script/,'&lt;script') unless opts[:script]
    value = value.gsub(/<link/,'&lt;link') unless opts[:link]
    value
  end

  def html_escape once=true
    self
      .sub(/^\s+/, '')
      .sub(/\s+$/, '')
      .gsub(/\s+/, ' ')
      .gsub("'", '&#39')
      .gsub('"', '&#34')
      .gsub('<', '&lt;')
      .gsub('>', '&gt;')
  end

  # result = ActiveSupport::Multibyte::Unicode.tidy_bytes(s.to_s).gsub(HTML_ESCAPE_ONCE_REGEXP, HTML_ESCAPE)
  #     s.html_safe? ? result.html_safe : result

  def trim(len)
    return self if self.length<len
    data = self.dup[0,len]+'&hellip;'
    data
  end

  def first
    self[0,1]
  end

  def last(num=1)
    len = self.length
    self[len-num, len]
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

  def parse_erb scope=nil
    ERB.new(self.gsub(/\n<%/, '<%')).result(scope ? scope.send(:binding) : binding)
  end

  def parameterize
    str_from = 'šđčćžŠĐČĆŽäÄéeöÖüüÜß'
    str_to   = 'sdcczSDCCZaAeeoOuuUs'

    self
      .tr(str_from, str_to)
      .sub(/[^\w+]$/, '')
      .downcase
      .gsub(/[^\w+]+/,'-')[0, 50]
  end
  alias :to_url :parameterize

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
    return true if suffix == self
    suffix.is_a?(String) && self[-suffix.length, suffix.length] == suffix && self != suffix
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
