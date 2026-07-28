require_relative './nav/base'
require_relative './nav/ref_string'
require_relative './nav/ref_uuid7'

module Lux
  class Application
    class Nav
      attr_accessor :format
      attr_reader :domain, :subdomain, :source_path

      # acepts path as a string
      def initialize request
        # lowercase path segments; for `key:value` segments only the key is lowercased
        @path        = (request.path.split('/').slice(1, 100) || []).map { |s| s.sub(/\A[^:]+/) { _1.downcase } }
        @request     = request

        set_variables
        set_domain request
        set_format

        # The path as the request arrived - lowercased, format and `key:value`
        # already stripped, but before `nav.map_path { }` classification, `nav.locale { }`
        # peeling or any app rewrite. #path is the working copy that all of those
        # mutate; this is what you snapshot against.
        #
        # A plain dup is enough: every later mutation (map!, []=, shift, unshift,
        # and the `@path = @path.map` in #map_path) replaces elements or the whole
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

      # get Url object initialized with request.url - relative
      # current.nav.url(:foo, 1).to_s # /path?foo=1
      def url *args
        if args.first
          Url.current.qs(*args)
        else
          Url.current
        end
      end

      # The working path: plain Strings for ordinary segments, a Nav::Base
      # instance for anything `nav.map_path` classified as an id. Rewritten in place
      # by `nav.map_path`, `nav.locale { }` and app code (`nav.path[1] = board.ref`,
      # `unshift`, ...). See #source_path for the version that arrived.
      def path
        @path
      end

      def path= list
        @path = list
      end

      # The working path with every classified id put back as the literal
      # `ref` placeholder - the URL's *shape* rather than its values.
      #
      #   /boards/abc123/edit
      #   path             ['boards', #<RefString "abc123">, 'edit']
      #   normalized_path  ['boards', 'ref', 'edit']
      #
      # This is what maps to disk: the auto-render template convention is
      # app/views/boards/ref/edit.haml. Unrelated to `Route#norm`, which is the
      # `-`/`_` equivalence used when comparing a single segment.
      def normalized_path
        @path.map { |el| el.is_a?(Base) ? 'ref' : el }
      end

      # Every classified id in the URL, in path order. Derived from @path, so
      # there is no second copy to fall out of sync with it.
      def refs
        @path.grep(Base).map(&:value)
      end

      # The first classified id in the URL, or nil. Read-only - classification
      # is #map_path.
      def ref
        refs.first
      end

      # Map id segments in the path to typed ref objects. One line in a router
      # before-filter, usually with no arguments:
      #
      #   nav.map_path                          # the app's Lux.config.ref_format
      #   nav.map_path :uuid7                   # a different registered format
      #   nav.map_path :string, upcase: true    # ... with attributes
      #   nav.map_path { |segment, list| ... }  # a custom rule
      #
      # A matched segment is replaced by a format instance carrying the value
      # (see Nav::Base); the rest are left alone. With no block the format's own
      # #valid? decides. With a block, the block decides per segment and the
      # format's #valid? is bypassed by design - you have already ruled:
      # * truthy return -> that value is the id (a literal `true` means the
      #                    segment itself)
      # * nil/false     -> segment left as-is
      #
      # The block is yielded the segment and the list built so far, so a rule can
      # look at what sits to its left. Declare only what you need - a one-arg
      # block is the common case.
      #
      # nav.map_path { |el| el.split('-').last.then { |p| Ref.is?(p) ? p : nil } }
      # /foo/title-cw7r/bar -> ['foo', #<RefString "cw7r">, 'bar'] -> nav.ref == 'cw7r'
      #
      # Segments that are no longer plain Strings (already classified, or set by
      # app code) are skipped, so re-running is idempotent. Returns nav.ref.
      def map_path format = nil, **attrs, &block
        klass, defaults = Base.resolve(format)
        attrs = defaults.merge(attrs)

        # built left to right so each match can see the segment before it, in
        # its already-classified form (see Nav::Base#path_before)
        @path = @path.each_with_object([]) do |el, list|
          list << (el.is_a?(::String) ? classify(el, klass, attrs, list, &block) : el)
        end

        refs.first
      end

      # removes leading www.
      # https://www.foo.bar/path -> https://foo.bar/path
      def remove_www
        url = Lux.current.request.url

        if url.include?('://www.')
          Lux.current.response.redirect_to url.sub('://www.', '://')
        end
      end

      # nav.rename_domain 'localhost', 'lvh.me'
      # http://localhost:3000/foo?bar=123 -> http://lvh.me:3000/foo?bar=123
      def rename_domain from_domain, to_domain
        if from_domain == @domain
          url = Url.new Lux.current.request.url
          Lux.current.response.redirect_to url.domain(to_domain).to_s
        end
      end

      # http://tiger.lvh.me:3000/foo?bar=1 -> http://tiger.lvh.me:3000
      def base
        @base ||= Lux.current.request.url.split('/').first(3).join('/')
      end

      def to_s
        @path.join('/').sub(/\/$/, '')
      end

      # Reader, and the locale-segment classifier - same shape as #map_path.
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
      # reflected. Classified segments render as their value, not as a placeholder.
      def pathname ends: nil, has: nil
        pn = '/' + @path.map(&:to_s).join('/')
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
          value = segment
          return segment unless klass.new(value, **attrs).valid?
        end

        klass.new value, path_before: list.last, **attrs
      end

      def set_variables
        # convert /foo/bar:baz to /foo?bar=baz
        while @path.last&.include?(':')
          key, val = @path.pop.split(':', 2)
          Lux.current.params[key.to_sym] ||= val
        end
      end

      # Known two-part TLDs where the domain is the third-from-last segment
      TWO_PART_TLDS = %w[
        co.uk co.nz co.in co.za co.jp co.kr co.il co.th
        com.au com.br com.sg com.hk com.mx com.ar com.tw
        org.uk org.au org.nz
        net.au net.nz
        ac.uk ac.nz
        gov.uk edu.au
      ].freeze

      def set_domain request
        begin
          parts = request.host.to_s.split('.')
        rescue NoMethodError
          raise Lux.error 400, 'Host name error'
        end

        if parts.last.is_numeric?
          @domain = request.host
        else
          count = 2
          count = 1 if parts.last == 'localhost'
          count = 3 if TWO_PART_TLDS.include?(parts.last(2).join('.'))

          @domain    = parts.pop(count).join('.')
          @domain    += ".#{parts.pop}" if @domain.length < 6
          @subdomain = parts.join('.')
        end
      end

      def set_format
        return unless @path.last
        parts = @path.last.split('.')

        if parts[1]
          @format    = parts.pop.to_s.downcase.to_sym
          @path.last = parts.join('.')
        end

        @path.shift if @path[0] == ''
      end
    end
  end
end
