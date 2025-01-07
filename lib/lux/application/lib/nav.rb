# experiment for different nav in rooter

module Lux
  class Application
    class Nav
      attr_accessor :format
      attr_reader :original, :domain, :subdomain, :querystring, :ids

      # acepts path as a string
      def initialize request
        @path        = request.path.split('/').slice(1, 100) || []
        @original    = @path.dup
        @request     = request
        @querystring = {}.to_hwia
        @ids         = []
        @shifted     = []

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

      def shift
        @path.shift.tap do |value|
          @shifted.push value
        end
      end

      # used to make admin.lvm.me/users to lvh.me/admin/users
      def unshift name = nil
        if name
          @path.unshift name
          @path = @path.flatten
          name
        else
          @path.unshift @shifted.pop
        end
      end

      # pop element of the path
      def pop replace_with = nil
        if block_given?
          if result = yield(@path.last)
            @path.pop
            @path.unshift replace_with if replace_with
            result
          end
        else
          @path.shift
        end
      end

      def last
      #   if block_given?
      #     # replace root in place if yields not nil
      #     return unless @path.last.present?
      #     result = yield(@path.last) || return
      #     @path.pop
      #     result
      #   else
          @path.last
      #   end
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

      def path *args
        if args.first
          # contruct path
          # /upload_dialog/is_image:true/model:posts/id:2/field:image_url
          # = nav.path :model, :id, :field -> /upload_dialog/model:posts/id:2/field:image_url
          parts  = @original.select {|el| !el.include?(':') }
          parts += args.map do |el|
            if value = Lux.current.params[el]
              [el, value].join(':')
            end
          end.compact
          '/' + parts.join('/')
        elsif block_given?
          @path = @path.map { _1.gsub('-', '_') }
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

      def id
        @ids.last
      end

      # replace nav path with id, when mached (works with resourceful routes map 'controler')
      # nav.path_id { _1.split('-').last.string_id rescue nil }
      # /foo/test-cbjy/bar -> ['foo', :id, 'bar]
      def path_id
        @path = @path.map do |el|
          if result = yield(el)
            @ids.push result
            :id
          else
            el
          end
        end

        @ids.last
      end

      def [] index
        @original[index]
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

        @path.shift if @path[0] == ''
      end
    end
  end
end
