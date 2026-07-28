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
    #
    # `:ref` is the one pattern matched by type rather than by text - it means
    # "a segment nav.ref classified as an id" (see #match_segment?).
    class Route
      def initialize nav
        @nav     = nav
        @offsets = [0]
      end

      def path
        @nav.path[@offsets.last..] || []
      end

      # #path with classified ids put back as the literal `ref` placeholder.
      # See Nav#normalized_path - this is the cursor-relative view of it.
      def normalized_path
        @nav.normalized_path[@offsets.last..] || []
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
        when ::String then match_segment?(root, pattern.sub(%r{^/}, ''))
        when ::Symbol then match_segment?(root, pattern)
        when ::Regexp then !!(pattern =~ root.to_s)
        when ::Array  then pattern.any? { |el| match?(el) }
        else false
        end
      end

      # Cursor-relative prefix match on one or more segments.
      #   start_with?(:spaces)         -> /spaces/*
      #   start_with?(:admin, :users)  -> /admin/users/*
      def start_with? *segments
        segments = segments.flatten
        return false if segments.empty?

        list = path.first(segments.length)
        return false if list.length < segments.length

        list.zip(segments).all? { |segment, pattern| match_segment?(segment, pattern) }
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
            captures[el[1..].to_sym] = segment_value(segment)
          else
            return nil unless match_segment?(segment, el)
          end
        end

        captures
      end

      # Number of segments an absolute pattern consumes.
      def capture_length pattern
        pattern.split('/').reject(&:empty?).length
      end

      private

      # `:ref` matches any segment `nav.ref` classified as an id, by type - a
      # literal URL segment spelled "ref" is not one. Everything else compares
      # as text.
      def match_segment? segment, pattern
        return segment.is_a?(Nav::Base) if norm(pattern) == 'ref'

        !segment.is_a?(Nav::Base) && norm(segment) == norm(pattern)
      end

      # A classified segment carries its own id (see Nav::Base), so a capture
      # that lands on one binds the value, not the placeholder.
      def segment_value segment
        segment.is_a?(Nav::Base) ? segment.value : segment
      end

      # `-` and `_` are the same character to the router. Applied to both sides
      # at compare time so nav.path is never rewritten.
      def norm value
        value.to_s.tr('-', '_')
      end
    end
  end
end
