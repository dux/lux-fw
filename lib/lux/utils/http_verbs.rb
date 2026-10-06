module Lux
  module Utils
    # The `allow` contract shared by Lux::Controller and Lux::Api: the declared
    # verbs REPLACE the default set (GET for controllers, POST for APIs), `:any`
    # (alias `:all`) turns the check off, and HEAD + OPTIONS ride along with GET.
    module HttpVerbs
      extend self

      ALL ||= %i(get head options post put patch delete trace).freeze

      # allow-style args -> [:get, :post] or :any. Raises on an unknown verb.
      def parse *verbs
        verbs = verbs.flatten.map { _1.to_s.downcase.to_sym }
        return :any if verbs.include?(:any) || verbs.include?(:all)

        verbs.each do |verb|
          next if ALL.include?(verb)
          raise ArgumentError, '"%s" is not a recognised HTTP verb (got: %s)' % [verb, ALL.join(', ')]
        end

        verbs.uniq
      end

      # parsed list -> Set of accepted verbs (adds HEAD + OPTIONS to GET), or :any
      def expand verbs
        return :any if verbs == :any

        Set.new(verbs).tap { |set| set.merge(%i[head options]) if set.include?(:get) }
      end

      def allowed? verbs, request_method
        set = expand(verbs)
        set == :any || set.include?(request_method.to_s.downcase.to_sym)
      end
    end
  end
end
