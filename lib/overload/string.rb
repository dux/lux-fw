require 'erb'
require 'cgi/escape'
require 'digest'

class String
  CONST_NAME ||= /\A(?:::)?[A-Z]\w*(?:::[A-Z]\w*)*\z/

  # 'User'.constantize? # User
  # 'UserFoo'.constantize? # nil
  # constantize itself comes from Sequel's inflector, loaded after this file
  def constantize?
    return unless CONST_NAME.match?(self)
    name = delete_prefix('::')
    Object.const_defined?(name) ? Object.const_get(name) : nil
  end

  # Output escaping. Haml runs with escape_html + use_html_safe, so `=` escapes
  # every printed string unless it answers html_safe?. A plain String never does.
  def html_safe?
    false
  end

  # Mark *trusted* markup as safe; templates print it as is. Not a sanitizer:
  # only <script>/<style> are disabled, event-handler attributes, javascript:
  # URLs and other tags pass through. Never call it on user-supplied HTML.
  #   = @post.body.html_unsafe
  #   = @page.head.html_unsafe(script: true, style: true)
  def html_unsafe script: false, style: false
    out = self
    out = out.gsub(/<(\/?script)/i, '&lt;\1') unless script
    out = out.gsub(/<(\/?style)/i, '&lt;\1') unless style
    Lux::SafeString.new(out)
  end

  # Entity-escaped copy, safe to print or to glue into markup built by hand.
  def html_escape
    Lux::SafeString.new(ERB::Util.html_escape(self))
  end

  # simple markdown: escaped text, line breaks and links
  def as_html
    html_escape
      .gsub($/, '<br />')
      .gsub(%r{https?://[^\s<]+?(?=(?:&quot;|&#39;|&gt;|[.,;:!?)])*(?:\s|<|\z))}) { %[<a href="#{$&}">#{$&.trim(40)}</a>] }
      .html_unsafe
  end

  def trim len
    length <= len ? self : self[0, len] + '...'
  end

  def first limit = 1
    self[0, limit]
  end

  def last num = 1
    num >= length ? dup : self[length - num, num]
  end

  def wrap node_name, opts={}
    return self unless node_name
    opts.tag(node_name, self)
  end

  # `'inner'.tag(:p, class: 'x')` -> '<p class="x">inner</p>'. The receiver is
  # the inner text. Provided by the vendored html-tag (see lib/lux/utils/html_tag/).
  def tag(node_name, **attrs, &block)
    inbound = HtmlTag::Inbound.new
    inbound.tag(node_name, self, **attrs, &block)
    inbound.render
  end

  def parse_erb scope = nil
    ERB.new(self).result(scope || binding)
  end

  def parameterize len = 50
    unicode_normalize(:nfkd)
      .gsub(/\p{Mn}/, '')
      .tr("\u0111\u0110\u0142\u0141\u00f8\u00d8", 'dDlLoO')
      .gsub("\u00df", 'ss')
      .downcase
      .gsub(/[^a-z0-9_+]+/, '-')[0, len]
      .gsub(/\A-+|-+\z/, '')
  end

  def qs_to_hash
    split('&').each_with_object({}) do |line, h|
      k, v = line.split('=', 2)
      h[CGI.unescape(k)] = CGI.unescape(v.to_s)
    end
  end

  def db_safe
    self.gsub(/[^0-9a-zA-Z_]/, '')
  end

  # starts_with? removed - use Ruby's built-in start_with? instead.

  ANSI_COLORS ||= {
    black: 30, red: 31, green: 32, yellow: 33, blue: 34,
    magenta: 35, cyan: 36, white: 37, gray: 90,
    light_black: 90, light_blue: 94
  }

  def colorize color
    "\e[#{ANSI_COLORS[color] || 0}m#{self}\e[0m"
  end

  def decolorize
    gsub(/\e\[\d+m/, '')
  end

  # percent-encoding valid in a path and a query (space -> %20); the one
  # convention Lux::Utils::Url.escape shares
  def escape
    CGI.escapeURIComponent(self)
  end

  # decodes both %20 and the form-style + as a space
  def unescape
    CGI.unescape self
  end

  def sha1
    Digest::SHA1.hexdigest self
  end

  def md5
    Digest::MD5.hexdigest self
  end

  def to_slug(len = 80) = parameterize(len).tr('_', '-')

  def remove_tags
    self.gsub(/<[^>]+>/, '')
  end

  def squish
    gsub(/[[:space:]]+/, " ")
    .strip
  end

  def indent amount = 2, char = ' '
    prefix = char * amount
    gsub(/^/, prefix)
  end
end
