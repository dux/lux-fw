# this should be done in every projet
# 
# module Sequel::Plugins::LuxTouch
#   module InstanceMethods
#     # used to touch changed columns, to clear both caches
#     # long: if org_id param changes from 3 to 5, we have to Org[3].touch and Org[5].touch
#     # usage
#     # touch_on :org_id
#     def touch_on name, klass=nil
#       klass ||= name.to_s.sub(/_ids?$/, '').classify.constantize

#       # get original and new link
#       list = column_changes[name].or([]) + [self[name]]
#       list
#         .flatten
#         .xuniq
#         .map { |id| klass[id]&.touch }
#     end

#     def touch
#       # if !column_changes[:updated_at] || (column_changes[:updated_at] && column_changes[:updated_at][0])
#         # we touck only if we have updated at filed
#         if db_schema[:updated_at]# && (Time.now - self[:updated_at]) > 1
#           key = 'lux-touch-%s-%s' % [self.class, id]
#           ap [:o, key, self.updated_at] if $debug
#           Lux.current.once key do
#             ap [:i, key, self.updated_at] if $debug
#             this.update updated_at: Time.now
#             Lux.cache.delete self.key
#           end
#         end
#       #end
#     end

#     def after_change
#       touch
#       super
#     end
#   end
# end

