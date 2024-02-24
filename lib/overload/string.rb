class String
  def constantize
    Object.const_get('::' + self)
  end

  # 'User'.constantize? # User
  # 'UserFoo'.constantize? # nil
  def constantize?
    Object.const_defined?('::' + self) ? constantize : nil
  end

  # prepare data for storage write, to make it safe to dump on screen without unescape
  def html_escape display = false
    # .gsub('<', '&lt;').gsub('>', '&gt;')
    # .gsub("'", '&#39').gsub('"', '&#34')
    self
      .gsub('<', display ? '&lt;' : '#LT;')
      .gsub(/\A^\s+|\s+\z/,'')
  end

  # restore original before storage read
  def html_unsafe full = false
    if full
      self
        .gsub('#LT;', '<')
        .gsub('$LT;', '<')
        .gsub('&lt;', '<')
        .gsub('&gt;', '>')
        .gsub('&#39', "'")
        .gsub('&#34', '"')
    else
      self.gsub('#LT;', '<')
    end
  end

  # export html without scripts and styles
  def html_safe full = false
    html_unsafe(full)
      .gsub(/<(\/?script)/i,'&lt;\1')
      .gsub(/<(\/?style)/i,'&lt;\1')
  end

  # simple markdown
  def as_html
    self
      .gsub($/, '<br />')
      .gsub(/(https?:\/\/[^\s<]+)/) { %[<a href="#{$1}">#{$1.trim(40)}</a>] }
  end

  def trim len
    return self if self.length<len
    data = self.dup[0,len]+'&hellip;'
    data
  end

  def first
    self[0,1]
  end

  def last num = 1
    len = self.length
    self[len-num, len]
  end

  # https://github.com/rgrove/sanitize
  def sanitize
    Sanitize.clean(self, :elements=>%w[span ul ol li b bold i italic u underline hr br p], :attributes=>{'span'=>['style']} )
  end

  def quick_sanitize
    out = self.gsub('<!--{tag}-->', '')
    out = out.gsub(/\sstyle="([^"]+)"/) do
      $1.start_with?('text-align:') ? $1 : ''
    end
    out
  end

  def wrap node_name, opts={}
    return self unless node_name
    opts.tag(node_name, self)
  end

  def fix_ut8
    self.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '?')
  end

  def parse_erb scope = nil
    ERB.new(self).result(scope || binding)
  end

  def parameterize
    str_from = 'šđčćžŠĐČĆŽäÄéeöÖüüÜß'
    str_to   = 'sdcczSDCCZaAeeoOuuUs'

    self
      .tr(str_from, str_to)
      .sub(/^[^\w+]/, '')
      .sub(/[^\w+]$/, '')
      .downcase
      .gsub(/[^\w+]+/,'-')[0, 50]
  end
  alias :to_url :parameterize

  def qs_to_hash
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
    CGI::escape(self).gsub('+', '%20')
  end

  def unescape
    CGI::unescape self
  end

  def sha1
    Digest::SHA1.hexdigest self
  end

  def md5
    Digest::MD5.hexdigest self
  end

  def extract_scripts! list: false
    scripts = []
    self.gsub!(/<script\b[^>]*>(.*?)<\/script>/im) { scripts.push $1; '' }
    list ? scripts : scripts.map{ "<script>#{_1}</script>"}.join($/)
  end

  def to_slug len = 80
    self.downcase.gsub(/[^\w]+/, '_').gsub(/_+/, '-').sub(/\-$/, '')[0, len]
  end

  def remove_tags
    self.gsub(/<[^>]+>/, '')
  end

end
