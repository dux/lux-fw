# @list = LinkedUser
#   .order(Sequel.desc(:updated_at))
#   .where(user_id: user.id)
#   .limit(20)
#   .all
#   .precache(:job_id)
#   .precache(:org_id, Organization)

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
      hash = db_schema[:ref] ? {ref: id} : {id: id}

      raise "id/ref not given for #{self}" unless id.present?

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

# class Array
#   # we have to call all on set and then precache
#   def precache field, klass=nil
#     list = self
#       .select{ |it| it && it[field] }
#       .map{ |it| it[field] }
#       .uniq
#       .sort

#     klass ||= field.to_s.sub(/_ids?$/, '').classify.constantize

#     for el in klass.where(id: list).all
#       Lux.current.cache("#{klass}/#{el.id}") { el.dup }
#     end

#     self
#   end
# end
