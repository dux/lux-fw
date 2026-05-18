# Cache-control policy for a response.
#
# Private cache is the default. Public cache is opt-in.
#
#   response.cache.public = true
#   response.cache.max_age = 10.minutes
#   response.cache.stale_while_revalidate = 1.hour
#   response.cache.no_store = true
#   response.cache.etag :users, User.max(:updated_at)
#
# Shortcuts on the Response object:
#
#   response.cache_public 10.minutes
#   response.no_store
#   response.etag :users, ts

module Lux
  class Response
    class CachePolicy
      attr_accessor :stale_while_revalidate
      attr_reader   :max_age

      def initialize response
        @response  = response
        @public    = false
        @no_store  = false
        @max_age   = 0
      end

      def max_age= age
        @max_age = age.to_i
        # positive max_age implies public cache (back-compat with response.max_age=)
        @public  = true if @max_age > 0
      end

      def public= value
        @public = !!value
      end

      def public?
        @public
      end

      def private?
        !public?
      end

      def no_store= value
        @no_store = !!value
      end

      def no_store?
        @no_store
      end

      def cached?
        @max_age > 0
      end

      # Public cache must never emit cookies. no-store also suppresses cookies.
      def allow_cookies?
        private? && !no_store?
      end

      def header_value
        return 'no-store' if no_store?

        parts = []
        parts << (public? ? 'public' : 'private, must-revalidate')
        parts << 'max-age=%d' % @max_age
        parts << 'stale-while-revalidate=%d' % @stale_while_revalidate.to_i if @stale_while_revalidate
        parts.join(', ')
      end

      # delegate to response so etag stays the canonical implementation
      def etag *args
        @response.etag(*args)
      end
    end
  end
end
