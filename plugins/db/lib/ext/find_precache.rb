# find with request-scoped and optional global caching
# Model.find(ref)   -> cached lookup by ref
# Model.take(ref)   -> find or nil (no exception)
# Model.find(hash)  -> Sequel's own find (first match or nil), which
#                      find_or_create and update_or_create rely on

# per-model `self.cache_ttl = 60`; subclasses read it through the ancestor walk
Sequel::Model.cattr :cache_ttl, class: true

class Sequel::Model
  module ClassMethods
    def take ref
      find ref
    rescue Sequel::Error
      nil
    end

    # find will cache all finds in a scope
    def find ref = nil, &block
      return first(ref, &block) if block || ref.is_a?(::Hash)
      return unless ref.present?

      key = "#{to_s}/#{ref}"
      hash = { ref: ref }

      Lux.current.cache key do
        row =
        if cattr.cache_ttl
          Lux.cache.fetch(key, ttl: cattr.cache_ttl) do
            self.first hash
          end
        else
          self.first hash
        end

        row || begin
          raise Sequel::Error, %[Record "#{ref}" not found in #{to_s}]
        end
      end
    end
  end
end
