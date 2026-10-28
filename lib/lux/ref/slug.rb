require_relative './short'

module Lux
  module Ref
    # A Short id at the end of a slug segment: /terapeut/dino-reic-<ref>.
    # A bare ref segment still matches. Subclass to add app rules.
    #
    #   Lux.config.ref_format = :slug
    class Slug < Short
      def extract segment
        super(segment.split('-').last)
      end
    end

    register :slug, Slug
  end
end
