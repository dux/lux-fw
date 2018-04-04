# module Sequel::Plugins::FilterWrappers
#   module ClassMethods

#     def validate &block
#       define_method :validate do
#         super
#         block.call
#       end
#     end

#     def before_save &block
#       define_method :before_save do
#         super
#         block.call
#       end
#     end

#   end
# end

# Sequel::Model.plugin :filter_wrappers