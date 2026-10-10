require 'erb'

class String
  def constantize
    Object.const_get('::' + self)
  end

  # 'User'.constantize? # User
  # 'UserFoo'.constantize? # nil
  def constantize?
    Object.const_defined?('::' + self) ? constantize : nil
  end

  # Output escaping. Haml runs with escape_html + use_html_safe, so `=` escapes
  # every printed string unless it answers html_safe?. A plain String never does.
  def html_safe?
    false
  end

  # Mark as markup that templates print as is. <script> and <style> are
  # neutralized unless allowed, so stored HTML cannot run code by default.
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
      .gsub(/(https?:\/\/[^\s<]+)/) { %[<a href="#{$1}">#{$1.trim(40)}</a>] }
      .html_unsafe
  end

  def trim len
    return self if self.length<len
    data = self.dup[0,len]+'...'
    data
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

  def attribute_safe
    self.gsub('"', '').gsub("'", '')
  end

  def db_safe
    self.gsub(/[^0-9a-zA-Z_]/, '')
  end

  # starts_with? removed - use Ruby's built-in start_with? instead.

  def span_green
    tag(:span, style: 'color: #080;')
  end

  def span_red
    tag(:span, style: 'color: #800;')
  end

  ANSI_COLORS = {
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

  def squish
    gsub(/[[:space:]]+/, " ")
    .strip
  end

  def indent amount = 2, char = ' '
    prefix = char * amount
    gsub(/^/, prefix)
  end
end

module Lux
  # Markup a template prints as is (html_safe? is true). Appending plain text
  # escapes it first, so `safe + user_text` stays safe. Any other String method
  # (gsub, strip, interpolation) returns a plain String - treated as text again.
  class SafeString < ::String
    # join parts into one safe string, escaping the parts that are plain text
    def self.join parts, separator = ''
      new parts.map { _1.to_s.html_safe? ? _1.to_s : ERB::Util.html_escape(_1.to_s) }.join(separator)
    end

    def html_safe?
      true
    end

    # String#to_s on a subclass returns a plain String copy
    def to_s
      self
    end

    def html_unsafe(**)
      self
    end

    def + other
      SafeString.new(super(safe(other)))
    end

    def concat *others
      super(*others.map { safe(_1) })
    end

    def << other
      concat other
    end

    private

    def safe other
      other = other.to_s
      other.html_safe? ? other : ERB::Util.html_escape(other)
    end

    # Haml's output buffer (see Lux::Template::HamlBuffer). Haml escapes before
    # it appends, so << is raw here; the buffer, and so any template block
    # that hands it back, is markup.
    class Buffer < SafeString
      def concat *parts
        ::String.instance_method(:concat).bind_call(self, *parts)
      end

      def << part
        concat part
      end
    end
  end
end
