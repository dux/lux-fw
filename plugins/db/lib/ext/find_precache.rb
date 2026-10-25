# find with request-scoped and optional global caching
# Model.find(ref)   -> cached lookup by ref, raises Lux.error.not_found (404)
# Model.take(ref)   -> find or nil (no exception)
# Model.find(hash)  -> Sequel's own find (first match or nil), which
#                      find_or_create and update_or_create rely on

# per-model `self.cache_ttl = 60`; subclasses read it through the ancestor walk
Sequel::Model.cattr :cache_ttl, class: true

class Sequel::Model
  module ClassMethods
    def take ref
      find_cached ref if ref.present?
    end

    # find will cache all finds in a scope
    def find ref = nil, &block
      return first(ref, &block) if block || ref.is_a?(::Hash)
      return unless ref.present?

      find_cached(ref) || raise(Lux.error.not_found(%[Record "#{ref}" not found in #{self}]))
    end

    private

    def find_cached ref
      key = "#{self}/#{ref}"
      hash = { ref: ref }

      Lux.current.cache key do
        if cattr.cache_ttl
          Lux.cache.fetch(key, ttl: cattr.cache_ttl) do
            self.first hash
          end
        else
          self.first hash
        end
      end
    end
  end
end
