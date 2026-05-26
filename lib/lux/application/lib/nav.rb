module Lux
  class Application
    class Nav
      attr_accessor :format
      attr_reader :domain, :subdomain, :refs

      # acepts path as a string
      def initialize request
        # lowercase path segments; for `key:value` segments only the key is lowercased
        @path        = (request.path.split('/').slice(1, 100) || []).map { |s| s.sub(/\A[^:]+/) { _1.downcase } }
        @request     = request
        @refs        = []

        set_variables
        set_domain request
        set_format
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

      def path ref = nil
        if block_given?
          # Classify path segments. The block decides per segment:
          # * truthy return -> stored in nav.refs, segment replaced by `ref` symbol
          # * nil/false     -> segment left as-is
          # * already a Symbol (idempotency) -> skipped entirely
          #
          # nav.path(:ref) {|el| el.split('-').last.then { |p| Ref.is?(p) ? p : nil } }
          # /foo/title-cw7r/bar -> ['foo', :ref, 'bar'] -> nav.ref == 'cw7r'
          unless ref
            raise ArgumentError.new('Default path not given as argument')
          end

          @path = @path.map do |el|
            next el if el.is_a?(Symbol)
            if result = yield(el)
              @refs.push result == true ? el : result
              ref
            else
              el
            end
          end

          @refs.last
        else
          @path
        end
      end

      def path= list
        @path = list
      end

      def ref
        @refs[0]
      end

      def ref= data
        @refs[0] = data
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

      # accept only two strings locale
      # nav.locale { _1.length == 2 ? _1 : nil }
      def locale
        if @locale
          return @locale.to_s == '' ? nil : @locale
        end

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
          Lux.error 400, 'Host name error'
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
