module Lux
  class Router
    class Nav
      attr_accessor :format
      attr_reader :domain, :source_path

      # acepts path as a string
      def initialize request
        # lowercase path segments; for `key:value` segments only the key is lowercased
        @path        = request.path.split('/').reject(&:empty?).first(100).map { |s| s.sub(/\A[^:]+/) { _1.downcase } }
        @request     = request

        set_variables
        set_domain request
        set_format

        # The path as the request arrived - lowercased, format and `key:value`
        # already stripped, but before `nav.map_path` classification, `nav.locale { }`
        # peeling or any app rewrite. The one place an id survives as its URL
        # text; #path is the working copy that all of those mutate.
        #
        # A plain dup is enough: every later mutation (map!, []=, shift, unshift,
        # and the `@path = ...` in #map_path) replaces elements or the whole
        # array, never mutates a segment string in place.
        @source_path = @path.dup.freeze
      end

      def root
        @path.first
      end

      def root= value
        @path[0] = value
      end

      # nav.root?(:admin) -> true if /admin/...
      def root? name
        root == name.to_s
      end

      def child
        @path[1]
      end

      def last
        @path.last
      end

      # Bare: the current subdomain. With a name: absolute URL on that subdomain
      # of the current domain (nil -> the domain itself), on the current path
      # unless one is given. session: true returns a /_lux_/handoff link on this
      # host that carries the session over when followed, see Session#handoff_link.
      #   nav.subdomain                                  # 'admin'
      #   nav.subdomain(:app, '/dashboard', session: true)
      def subdomain *args, session: false
        return @subdomain if args.empty?

        name, path = args
        url = Url.current.subdomain(name)
        url.path path if path
        session ? Lux.ctx.session.handoff_link(url.url) : url.url
      end

      # get Url object initialized with request.url - relative
      # Lux.ctx.nav.url(:foo, 1).to_s # /path?foo=1
      def url *args
        if args.first
          Url.current.qs(*args)
        else
          Url.current
        end
      end

      # The working path: plain Strings, plus a Lux::Ref::Base for each segment
      # `nav.map_path` classified as an id - it reads 'ref' (the route shape)
      # and `.value` is the id. Rewritten in place by `nav.map_path`,
      # `nav.locale { }` and app code (`nav.path[1] = board.ref`, `unshift`, ...).
      # See #source_path for the version that arrived.
      def path
        @path
      end

      def path= list
        @path = list
      end

      # The `.value` of every id element in the path, in path order. Derived
      # from @path, so there is no second copy to fall out of sync with it.
      def refs
        @path.grep(Lux::Ref::Base).map(&:value)
      end

      # The first id in the path, or nil. Read-only - classification is
      # #map_path, or a resourceful router reading an id by position (#ref_at!).
      def ref
        refs.first
      end

      # Marks the segment at `index` as an id by its position, the way a
      # resourceful router reads /boards/<id>: it becomes an element of the
      # app's ref format carrying the segment as is. Returns nav.ref.
      def ref_at! index
        @path[index] = Lux::Ref.build(@path[index].to_s)
        ref
      end

      # Map id segments in the path to typed ref objects. One line in a router
      # before-filter, usually with no arguments:
      #
      #   nav.map_path                          # the app's Lux.config.ref_format
      #   nav.map_path :uuid7                   # a different registered format
      #   nav.map_path :string, upcase: true    # ... with attributes
      #   nav.map_path { |segment, list| ... }  # a custom rule
      #
      # A matched segment is replaced by a format instance that reads 'ref' and
      # carries the id as `.value` (see Lux::Ref::Base); the rest are left alone.
      # With no block the format's own #extract decides. With a block, the block
      # decides per segment and the format is bypassed by design - you have
      # already ruled:
      # * truthy return -> that value is the id (a literal `true` means the
      #                    segment itself)
      # * nil/false     -> segment left as-is
      #
      # The block is yielded the segment and the list built so far, so a rule can
      # look at what sits to its left. Declare only what you need - a one-arg
      # block is the common case.
      #
      # nav.map_path { |el| el.split('-').last.then { |p| Lux::Ref.is?(p) ? p : nil } }
      # /foo/title-cw7r/bar -> ['foo', 'ref', 'bar'], nav.path[1].value == 'cw7r'
      #
      # Elements that are already ids are skipped, so re-running is
      # idempotent. Returns nav.ref.
      def map_path format = nil, **attrs, &block
        klass, defaults = Lux::Ref.resolve(format)
        attrs = defaults.merge(attrs)

        # built left to right so a block can see the segments before it, in
        # their already-classified form
        @path = @path.each_with_object([]) do |el, list|
          plain = el.is_a?(::String) && !el.is_a?(Lux::Ref::Base)
          list << (plain ? classify(el, klass, attrs, list, &block) : el)
        end

        refs.first
      end

      # removes leading www.
      # https://www.foo.bar/path -> https://foo.bar/path
      def remove_www
        url = Lux.ctx.request.url

        if url.include?('://www.')
          Lux.ctx.response.redirect_to url.sub('://www.', '://')
        end
      end

      # nav.rename_domain 'localhost', 'lvh.me'
      # http://localhost:3000/foo?bar=123 -> http://lvh.me:3000/foo?bar=123
      def rename_domain from_domain, to_domain
        if from_domain == @domain
          url = Url.new Lux.ctx.request.url
          Lux.ctx.response.redirect_to url.domain(to_domain).to_s
        end
      end

      # http://tiger.lvh.me:3000/foo?bar=1 -> http://tiger.lvh.me:3000
      def base
        @base ||= Lux.ctx.request.url.split('/').first(3).join('/')
      end

      def to_s
        text_path.join('/').sub(/\/$/, '')
      end

      # Reader, and the locale-segment classifier.
      # nav.locale { _1.length == 2 ? _1 : nil }
      def locale
        if @locale
          return @locale.to_s == '' ? nil : @locale
        end

        # reader form: nothing resolved yet and no block to resolve it with
        return nil unless block_given?

        if @path[0].to_s.downcase =~ /^[a-z]{2}(-[a-z]{2})?$/
          if @locale = yield(@path[0])
            @path.shift
          else
            @locale = ''
          end
        end

        @locale
      end

      def locale= name
        @locale = name.present? ? name.to_s : nil
      end

      def [] index
        @path[index]
      end

      # Canonical path string, or test path inclusion.
      # Reads from @path, so format/locale stripping and any app rewrite are
      # reflected. Ids print as their value.
      def pathname ends: nil, has: nil
        pn = '/' + text_path.join('/')
        return pn.include?("/#{has}") if has
        return pn.end_with?("/#{ends}") if ends
        pn
      end

      private

      # One segment through the classifier. Returns a format instance on a
      # match, or the segment untouched.
      def classify segment, klass, attrs, list, &block
        if block
          # segment first so a one-arg block keeps working; the list is there
          # for rules that need to see what came before. Arity-checked because a
          # lambda classifier (`->(el) { }`) raises on a two-arg call, unlike a
          # plain block which would just drop the extra.
          result = block.arity == 1 ? block.call(segment) : block.call(segment, list)
          return segment unless result
          value = result == true ? segment : result
        else
          value = klass.new(nil, **attrs).extract(segment) or return segment
        end

        klass.new value, **attrs
      end

      # the path as URL text - an id element prints its value, not 'ref'
      def text_path
        @path.map { _1.is_a?(Lux::Ref::Base) ? _1.value.to_s : _1.to_s }
      end

      def set_variables
        # convert /foo/bar:baz to /foo?bar=baz
        while @path.last&.include?(':')
          key, val = @path.pop.split(':', 2)
          Lux.ctx.params[key.to_sym] ||= val
        end
      end

      # one domain parser for Nav and Url, so the TLD rules cannot drift apart
      def set_domain request
        host = begin
          request.host
        rescue NoMethodError
          raise Lux.error 400, 'Host name error'
        end

        subdomain, @domain = Lux::Utils::Url.split_host(host)
        @subdomain = subdomain.to_s
      end

      def set_format
        return unless @path.last
        parts = @path.last.split('.')

        if parts[1]
          @format    = parts.pop.to_s.downcase.to_sym
          @path.last = parts.join('.')
        end
      end
    end
  end
end
