# experiment for different nav in rooter

module Lux
  class Application
    class Nav
      attr_accessor :format
      attr_reader :original, :domain, :subdomain, :querystring

      # acepts path as a string
      def initialize request
        @path        = request.path.split('/').slice(1, 100) || []
        @original    = @path.dup
        @request     = request
        @querystring = {}.to_hwia

        set_variables
        set_domain request
        set_format
      end

      # if block given, eval and shift or return nil
      def root sub_nav=nil
        raise 'Does not accept blocks' if block_given?
        sub_nav ? ('%s/%s' % [@path.first, sub_nav]) : @path.first
      end

      def root= value
        @path[0] = value
      end

      # shift element of the path
      # or eval block on path index and slice if true
      def shift index = 0
        return unless @path[index].present?

        if block_given?
          result = yield(@path[index]) || return

          if index == 0
            active_shift
          else
            @path.slice!(index, 1)
          end

          result
        else
          active_shift
        end
      end

      # used to make admin.lvm.me/users to lvh.me/admin/users
      def unshift name
        @path.unshift name
        @path = @path.flatten
        name
      end

      def last
        if block_given?
          # replace root in place if yields not nil
          return unless @path.last.present?
          result = yield(@path.last) || return
          @path.pop
          result
        else
          @path.last
        end
      end

      def active
        @active
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

      # contruct path
      # /upload_dialog/is_image:true/model:posts/id:2/field:image_url
      # = nav.path :model, :id, :field -> /upload_dialog/model:posts/id:2/field:image_url
      def path *args
        if args.first
          parts  = @original.select {|el| !el.include?(':') }
          parts += args.map {|el| [el, Lux.current.params[el] || Lux.error("qs param [#{el}] not found")].join(':') }
          '/' + parts.join('/')
        else
          @path
        end
      end

      def path= list
        @path = list
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
        Lux.current.request.url.split('/').first(3).join('/')
      end

      def to_s
        @path.join('/').sub(/\/$/, '')
      end

      private

      def set_variables
        # convert /foo/bar:baz to /foo?bar=baz
        while @path.last&.include?(':')
          key, val = @path.pop.split(':', 2)
          @querystring[key] = val
          Lux.current.params[key.to_sym] ||= val
        end
      end

      def set_domain request
        begin
          # NoMethodError
          # Message undefined method `start_with?' for nil:NilClass
          # gems/rack-2.2.4/lib/rack/request.rb:567:in `wrap_ipv6'
          parts = request.host.to_s.split('.')
        rescue NoMethodError
          raise Lux::Error.bad_request('Host name error')
        end

        if parts.last.is_numeric?
          @domain = request.host
        else
          count = 2
          count = 1 if parts.last == 'localhost'
          count = 3 if parts.last(2).join('.') == 5 # foo.co.uk

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
      end

      def active_shift
        @active = @path.shift
      end
    end
  end
end
