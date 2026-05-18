module Lux
  class Application
    # Per-request router cursor over `nav.path`. Does not mutate nav.
    # Maintains an offset stack so nested `map` scopes can be entered/exited
    # without rewriting the canonical path.
    class Route
      def initialize nav
        @nav     = nav
        @offsets = [0]
      end

      def path
        @nav.path[@offsets.last..] || []
      end

      def root
        path.first
      end

      def child
        path[1]
      end

      def consumed
        @nav.path[0, @offsets.last] || []
      end

      def with_scope n
        @offsets.push(@offsets.last + n)
        yield
      ensure
        @offsets.pop
      end
    end
  end
end
