# # used to fix array and hash fields, to allways return prmitive types

# class Sequel::Model
#   module ClassMethods
#     def fix_field name
#       schema = db_schema[name][:db_type]

#       if schema.include?('[]')
#         # return array primitive
#         self.class_eval %[
#           def #{name}
#             if self[:#{name}].class == String
#               self[:#{name}].split(/,\s*/)
#             else
#               self[:#{name}].or([]).to_a
#             end
#           end

#           def #{name}= data
#             self[:#{name}] = data.class == String ? data.split(/,\s*/) : data.to_a
#           end
#         ]
#       elsif schema == 'numeric'
#         # return float primitive
#         self.class_eval %[
#           def #{name}
#             value = self[:#{name}]
#             value.nil? ? nil : value.to_f
#           end
#         ]
#       else
#         raise "not defiend for #{name}:#{schema}"
#       end
#     end
#   end

#   module InstanceMethods
#   end
# end
