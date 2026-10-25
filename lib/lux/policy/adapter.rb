require_relative './proxy'

module Lux
  class Policy
    # Mix into models to enable @model.can(@user).read?
    #   class ApplicationModel
    #     include Lux::Policy::Model
    #   end
    module Model
      def can user = nil
        Lux::Policy.can model: self, user: user
      end
    end

    # Mix into routers for authorize / is_authorized?.
    # Included into Lux::Router (lib/lux/router/router.rb).
    module Authorize
      def authorize result = false
        if (block_given? ? yield : result)
          @_is_policy_authorized = true
        else
          Lux::Policy.error('Authorize did not pass truthy value')
        end
      end

      def is_authorized?
        @_is_policy_authorized == true
      end

      def is_authorized!
        if is_authorized?
          true
        else
          Lux::Policy.error('Request is not authorized!')
        end
      end
    end
  end
end
