# module Sequel::Plugins::RemoteDb
#   LUX_REMOTE_DB ||= {}

#   module ClassMethods
#     def remote_db value
#       LUX_REMOTE_DB[self.to_s] = value
#     end

#     def __modelize data
#       # refactor with self.class.load data
#       new.tap do |model|
#         model.instance_exec { @values = data }
#       end
#     end

#     def __conn
#       LUX_REMOTE_DB[self.to_s]
#     end

#     def find id
#       __modelize __conn[to_s.tableize.to_sym].where(id:id).first
#     end
#   end

#   module DatasetMethods
#     def count
#       custom = sql.sub 'SELECT * ', 'SELECT count(id) as cnt '
#       model.__conn.fetch(custom).first[:cnt]
#     end

#     def each &block
#       model.__conn.fetch(sql).each do |row|
#         block.call self.model.__modelize(row)
#       end
#     end
#   end

#   module InstanceMethods

#   end
# end
