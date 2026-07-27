module Lux
  class Application
    # Per-request router cursor over `nav.path`, and the single owner of path
    # matching. Does not mutate nav - an offset stack lets nested `map` scopes
    # and controller `filter` blocks be entered and exited without rewriting
    # the canonical path.
    #
    # Everything that asks "does the URL look like X?" goes through here:
    # `map` / `root` (match?), controller `filter` (start_with?) and absolute
    # `map '/a/:b'` (capture). That is also the only place `-` and `_` are
    # treated as the same character, so nav.path keeps the original spelling
    # and slug lookups still work.
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

      # Single-segment predicate against the cursor root. No side effects.
      #   match?('admin') / match?(:admin) / match?(%r{^@}) / match?([:a, :b])
      def match? pattern
        case pattern
        when ::String then norm(root) == norm(pattern.sub(%r{^/}, ''))
        when ::Symbol then norm(root) == norm(pattern)
        when ::Regexp then !!(pattern =~ root.to_s)
        when ::Array  then pattern.any? { |el| match?(el) }
        else false
        end
      end

      # Cursor-relative prefix match on one or more segments.
      #   start_with?(:spaces)         -> /spaces/*
      #   start_with?(:admin, :users)  -> /admin/users/*
      def start_with? *segments
        segments = segments.flatten.map { norm(_1) }
        return false if segments.empty?

        path.first(segments.length).map { norm(_1) } == segments
      end

      # Absolute path pattern with `:name` placeholders, matched from the URL
      # root (not the cursor). Returns the captures hash on a match, else nil.
      # An empty captures hash is still a match, so test with `.nil?`.
      # A placeholder needs a segment to bind - '/users/:id' does not match
      # bare '/users'.
      #   capture('/city/:name') -> { name: 'zagreb' }
      def capture pattern
        parts    = pattern.split('/').reject(&:empty?)
        captures = {}

        parts.each_with_index do |el, i|
          segment = @nav.path[i]

          if el.start_with?(':')
            return nil if segment.nil?
            captures[el[1..].to_sym] = segment_value(segment, i)
          else
            return nil unless norm(el) == norm(segment)
          end
        end

        captures
      end

      # Number of segments an absolute pattern consumes.
      def capture_length pattern
        pattern.split('/').reject(&:empty?).length
      end

      private

      # `nav.ref { }` replaces id segments with the `:ref` symbol and
      # moves the values to `nav.refs`, so a capture that lands on one has to
      # read the value back by position.
      def segment_value segment, index
        return segment unless segment == :ref

        @nav.refs[@nav.path[0, index].count(:ref)]
      end

      # `-` and `_` are the same character to the router. Applied to both sides
      # at compare time so nav.path is never rewritten.
      def norm value
        value.to_s.tr('-', '_')
      end
    end
  end
end
