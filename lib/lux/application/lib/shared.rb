module Lux
  class Application
    module Shared
      def current
        Lux.current
      end

      def request
        Lux.current.request
      end

      def response
        Lux.current.response
      end

      def session
        Lux.current.session
      end

      def params opts=nil, &block
        if block_given?
          Typero.schema(&block).validate Lux.current.request.params, opts do |field, error|
            error 'Parameter "%s" error: %s' % [field, error]
          end
        end

        Lux.current.params
      end

      def nav
        Lux.current.nav
      end

      def body?
        Lux.current.response.body?
      end

      def redirect_to where, flash={}
        Lux.current.response.redirect_to where, flash
      end

      def user
        User.current
      end
    end
  end
end
