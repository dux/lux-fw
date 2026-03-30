# Backward compatibility module - delegates to lux.*
module Lux
  class Application
    module Shared
      def request;     lux.request;  end
      def response;    lux.response; end
      def session;     lux.session;  end
      def params;      lux.params;   end
      def nav;         lux.nav;      end
      def current;     lux;          end
      def user;        lux.user;     end

      def redirect_to where, flash = {}
        lux.response.redirect_to where, flash
      end
    end
  end
end
