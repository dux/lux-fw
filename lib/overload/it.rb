# class Array
#   def it
#     @_it
#   end

#   # list.xeach { it.foo }
#   def xeach &block
#     each do |_|
#       @_it = _
#       instance_eval &block
#     end
#   end

#   # list.xmap { it * 2 }
#   def xmap &block
#     map do |_|
#       @_it = _
#       instance_eval &block
#     end
#   end

#   # list.xselect { it.class != Module }
#   def xselect &block
#     select do |_|
#       @_it = _
#       instance_eval &block
#     end
#   end
# end
