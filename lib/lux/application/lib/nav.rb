# experiment for different nav in rooter

module Lux
  class Application
    class Nav
      attr_accessor :path, :id, :format
      attr_reader :original, :domain, :subdomain, :namespace

      # acepts path as a string
      def initialize request
        @path         = request.path.split('/').slice(1, 100) || []
        @original     = @path.dup

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
      def shift index=0
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

      def to_s
        @path.join('/').sub(/\/$/, '')
      end

      private

      def set_variables
        # convert /foo/bar:baz to /foo?bar=baz
        while @path.last&.include?(':')
          key, val = @path.pop.split(':')
          Lux.current.request.params[key.to_sym] ||= val
        end
      end

      def set_domain request
        # localtest.me
        parts = request.host.split('.')
        if parts.last.is_numeric?
          @domain = request.host
        else
          @domain    = parts.pop(2).join('.')
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
