module Lux
  class Application
    class Nav
      attr_accessor :format
      attr_reader :domain, :subdomain, :refs, :source_path

      # acepts path as a string
      def initialize request
        # lowercase path segments; for `key:value` segments only the key is lowercased
        @path        = (request.path.split('/').slice(1, 100) || []).map { |s| s.sub(/\A[^:]+/) { _1.downcase } }
        @request     = request
        @refs        = []

        set_variables
        set_domain request
        set_format

        # The path as the request arrived - lowercased, format and `key:value`
        # already stripped, but before `nav.ref { }` classification, `nav.locale { }`
        # peeling or any app rewrite. #path is the working copy that all of those
        # mutate; this is what you snapshot against.
        #
        # A plain dup is enough: every later mutation (map!, []=, shift, unshift,
        # and the `@path = @path.map` in #ref) replaces elements or the whole
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

      # The working path. Rewritten in place by `nav.ref { }`, `nav.locale { }` and
      # app code (`nav.path[1] = board.ref`, `unshift`, ...). See #source_path for
      # the version that arrived.
      def path
        @path
      end

      def path= list
        @path = list
      end

      # Reader, and the id-segment classifier.
      #
      # Declare what an id looks like once, from a router before-filter:
      #
      #   nav.ref { |el| Ref.is?(el) ? el : nil }
      #
      # The block decides per segment:
      # * truthy return -> pushed to nav.refs, segment replaced by the `:ref`
      #                    symbol (a literal `true` stores the segment itself)
      # * nil/false     -> segment left as-is
      # * already a Symbol (idempotency) -> skipped entirely
      #
      # nav.ref { |el| el.split('-').last.then { |p| Ref.is?(p) ? p : nil } }
      # /foo/title-cw7r/bar -> ['foo', :ref, 'bar'] -> nav.ref == 'cw7r'
      #
      # With no block it reads the first extracted ref - same value the block form
      # returns. Multiple ids in one URL stack up in nav.refs, in path order.
      def ref
        return @refs.first unless block_given?

        @path = @path.map do |el|
          next el if el.is_a?(Symbol)
          if result = yield(el)
            @refs.push result == true ? el : result
            :ref
          else
            el
          end
        end

        @refs.first
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

      # Reader, and the locale-segment classifier - same shape as #ref.
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
      # Reads from @path so :ref symbols and format/locale stripping are reflected.
      def pathname ends: nil, has: nil
        pn = '/' + @path.map(&:to_s).join('/')
        return pn.include?("/#{has}") if has
        return pn.end_with?("/#{ends}") if ends
        pn
      end

      private

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
