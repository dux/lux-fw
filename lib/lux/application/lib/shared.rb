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

      def params
        Lux.current.request.params
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

      # Triggers HTTP page error
      # ```
      # error.not_found
      # error.not_found 'Doc not fount'
      # error(404)
      # error(404, 'Doc not fount')
      # ```
      def error code=nil, message=nil
        if code
          error = Lux::Error.new code
          error.message = message if message
          raise error
        else
          Lux::Error::AutoRaise
        end
      end
    end
  end
end
