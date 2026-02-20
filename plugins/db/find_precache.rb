# find with request-scoped and optional global caching
# Model.find(ref)   -> cached lookup by ref
# Model.take(ref)   -> find or nil (no exception)

class Sequel::Model
  module ClassMethods
    def include _
      self.cattr :cache_ttl, class: true
      super
    end

    def take id
      find id
    rescue
      nil
    end

    # find will cache all finds in a scope
    def find id
      return unless id.present?

      key = "#{to_s}/#{id}"
      hash = { ref: id }

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
          raise(%[Record "#{id}" not found in #{to_s}])
        end
      end
    end
  end

  module InstanceMethods
  end
end
