# frozen_string_literal: true

# Vendored from the `lux-url` gem (~/dev/dux/gems/lux-url). Wrapped under
# Lux::Utils::Url; top-level `Url` constant preserved as an alias so
# existing call sites keep working.
#
# u = Lux.url('https://www.YouTube.com/watch?t=1260&v=cOFSX6nezEY')
# u.delete :t
# u.hash '160s'
# u.to_s -> 'https://com.youtube.www/watch?v=cOFSX6nezEY#160s'

require 'cgi'

module Lux
  module Utils
    class Url
      # internal state container; qs is the ?a=1 hash, qs_path is the /a:1 hash, qs_hash is the #fragment
      OPTS ||= Struct.new(:proto, :port, :subdomain, :domain, :locale, :path, :qs, :qs_hash, :qs_path)

      # default ports stripped from rendered URLs when proto matches
      DEFAULT_PORTS ||= { 'http' => '80', 'https' => '443', 'ws' => '80', 'wss' => '443' }.freeze

      # locales accepted as a path prefix: "en" or "en-UK"
      LOCALE_RE ||= /\A[a-z]{2}(-[A-Z]{2})?\z/

      class << self
        # get current Url, overload for usage outside Lux
        def current
          new Lux.current.request.url
        end

        # host of the current request (no proto, no port)
        def host
          current.host
        end

        # swap the locale on the current request and return its relative form
        def locale loc
          u = current
          u.locale loc
          u.relative
        end

        # change current subdomain
        def subdomain name, in_path=nil
          b = current.subdomain(name)
          b.path in_path if in_path
          b.url
        end

        # set a query string on the current request and return its relative form
        def qs name, value
          current.qs(name, value).relative
        end

        # path qs /foo/bar:baz; also clears the matching ?name= if present
        def pqs name, value
          url = current.pqs(name, value)
          url.qs name, nil
          url.relative
        end

        # same as force qs but remove value if selected
        def toggle name, value
          value = nil if Lux.current.params[name].to_s == value.to_s
          qs name, value
        end

        # for search
        # Url.prepare_qs(:q) -> /foo?bar=1&q=
        def prepare_qs name
          url = current.delete(name).relative
          url += url.index('?') ? '&' : '?'
          "#{url}#{name}="
        end

        # CGI escape; nil-safe (returns '' for nil)
        def escape str=nil
          CGI::escape(str.to_s)
        end

        # CGI unescape; nil-safe (returns '' for nil)
        def unescape str=nil
          CGI::unescape(str.to_s)
        end

        # origin of the current request: proto://host[:port]
        def root
          new(Lux.current.request.url).host_with_port
        end
      end

      ###

      # parses an absolute or relative URL into @opt. Order:
      #   1. split off ?qs and #fragment
      #   2. if absolute, extract proto, host, port, domain, subdomain (co.uk handled by length heuristic)
      #   3. peel locale prefix (xx or xx-YY) and trailing /key:value segments off the path
      def initialize url
        @opt = OPTS.new

        url, qs_part = url.split('?', 2)

        # querysting hash
        qs_part, @opt.qs_hash = qs_part.to_s.split('#')
        @opt.qs_hash = '#%s' % @opt.qs_hash if @opt.qs_hash

        # querystring
        @opt.qs = qs_part.to_s.split('&').inject({}) do |qs, el|
          parts = el.split('=', 2)
          qs[parts[0]] = Lux::Utils::Url.unescape parts[1]
          qs
        end

        # domain and subdomain
        if url =~ %r{^\w+://}
          @opt.proto, _, host, @opt.path = url.split '/', 4

          @opt.proto = @opt.proto.sub(':', '')

          host, @opt.port = host.split(':', 2)
          @opt.port = nil if @opt.port.to_s.blank? || @opt.port == DEFAULT_PORTS[@opt.proto]

          # domain and subdomain
          parts = host.split('.').map(&:downcase)
          @opt.domain = parts.pop(2)
          @opt.domain.unshift parts.pop if @opt.domain.join('').length == 4 # co.uk
          @opt.domain = @opt.domain.join('.')
          @opt.subdomain = parts.first ? parts.join('.') : nil
        else
          @opt.path = url.to_s.sub(%r{^/}, '')
        end

        # check for locale
        @opt.qs_path ||= {}
        parts = @opt.path.to_s.split('/')
        if parts[0] =~ LOCALE_RE
          @opt.locale = parts.shift
        end

        while parts.last&.include?(':')
          key, value = parts.pop.split(':')
          @opt.qs_path[key] = value
        end

        @opt.path   = parts.join('/')

        @opt.path = '' if @opt.path.blank?
      end

      # returns a relative url primed for appending a value to `name`, e.g. "/foo?bar=1&q="
      def prepare_qs name
        url = delete(name).relative
        url += url.index('?') ? '&' : '?'
        "#{url}#{name}="
      end

      # reader when called bare; writer (chainable) when given a value
      def domain what=nil
        if what
          @opt.domain = what
          self
        else
          @opt.domain
        end
      end
      alias :domain= :domain

      # reader/writer; pass nil (or '') to clear -> apex/root. Uses a sentinel so
      # a bare call reads while an explicit nil clears the subdomain.
      def subdomain name = :_nil
        return @opt.subdomain if name == :_nil
        @opt.subdomain = name.to_s.empty? ? nil : name
        self
      end
      alias :subdomain= :subdomain

      # full host: subdomain.domain (or just domain)
      def host
        @opt.subdomain ? [@opt.subdomain, @opt.domain].join('.') : @opt.domain
      end

      # origin string: proto://host[:port]; empty when no proto/host (relative urls)
      def host_with_port
        return '' unless @opt.proto && host
        port_part = @opt.port.to_s.blank? ? '' : ":#{@opt.port}"
        "#{@opt.proto}://#{host}#{port_part}"
      end

      # getter renders /locale/path/key:val; setter strips leading slash and is chainable
      def path val=nil
        if val
          @opt.path = val.sub /^\//, ''
          return self
        else
          parts = []
          parts << @opt.locale if @opt.locale
          parts.concat(@opt.path.to_s.split('/')) unless @opt.path.blank?
          parts.concat @opt.qs_path.to_a
            .select{ !_1[1].blank? }
            .map{ "#{_1[0]}:#{_1[1]}"}
          "/#{parts.join('/')}"
        end
      end
      alias :path= :path

      # remove one or more keys from the query string; chainable
      def delete *keys
        keys.map{ |key| @opt.qs.delete(key.to_s) }
        self
      end

      # set the #fragment; chainable (shadows Object#hash, so Url instances aren't safe as Hash keys)
      def hash val
        @opt.qs_hash = "##{val}"
        self
      end

      def port
        @opt.port
      end

      def proto
        @opt.proto
      end

      # four modes: bare -> full qs hash; (hash) -> bulk merge (nil values delete);
      # (name) -> read value (falls back to qs_path); (name, value) -> write (nil deletes)
      def qs name=nil, value=:_nil
        return @opt.qs unless name

        if name.is_a?(Hash)
          name.each do |k, v|
            v.nil? ? @opt.qs.delete(k.to_s) : @opt.qs[k.to_s] = v
          end
          return self
        end

        name = name.to_s

        if value != :_nil
          value.nil? ? @opt.qs.delete(name) : @opt.qs[name] = value
          self
        else
          @opt.qs[name] || @opt.qs_path[name]
        end
      end

      # path query string -> /foo/bar:baz
      def pqs name = nil, value = :_nil
        if value != :_nil
          @opt.qs_path[name.to_s] = CGI::escape value.to_s
          self
        elsif name
          @opt.qs_path[name.to_s]
        else
          @opt.qs_path
        end
      end
      alias :path_qs :pqs

      # tokens after a leading ':' in the path, e.g. /:a:b/x -> ['a', 'b']
      def path_prefix
        if @opt.path[0, 1] == ':'
          @opt.path.split(':', 2)[1].split('/').first.split(':')
        else
          []
        end
      end

      # reader/writer; pass nil to clear
      def locale name=nil
        if name
          @opt.locale = name
          self
        else
          @opt.locale
        end
      end

      # absolute form: origin + path + ?qs + #fragment
      def url
        [host_with_port, path, qs_val, @opt.qs_hash].join('')
      end

      # relative form: path + ?qs + #fragment (no origin); collapses only a leading run of slashes
      def relative
        [path, qs_val, @opt.qs_hash].join('').sub(%r{^/+}, '/')
      end

      # absolute if a domain is known, else relative
      def to_s
        @opt.domain ? url : relative
      end

      # qs shortcut: url[:foo] === url.qs(:foo)
      def [] key
        qs key
      end

      # qs writer (bypasses sentinel-based dispatch in #qs)
      def []= key, value
        @opt.qs[key.to_s] = value
      end

      # structured snapshot of all parsed fields
      def to_h
        {
          proto:  @opt.proto,
          port:   @opt.port,
          domain: {
            full:      host,
            domain:    @opt.domain,
            subdomain: subdomain
          },
          locale: @opt.locale,
          path:   @opt.path,
          qs:     @opt.qs,
          hash:   @opt.qs_hash
        }
      end

      # pretty-printed JSON of to_h
      def to_json
        JSON.pretty_generate(to_h)
      end

      private

      # renders ?a=1&b=2 with keys sorted alphabetically (stable across calls)
      def qs_val
        ret = []
        if @opt.qs.keys.length > 0
          ret.push '?' + @opt.qs.keys.sort.map{ |key| "#{key}=#{Lux::Utils::Url.escape(@opt.qs[key].to_s)}" }.join('&')
        end
        ret.join('')
      end
    end
  end
end

# Back-compat top-level alias. Keeps existing `Url.new`, `Url.current`,
# `Url.escape` call sites working unchanged.
Url = Lux::Utils::Url unless defined?(Url) && Url.equal?(Lux::Utils::Url)
