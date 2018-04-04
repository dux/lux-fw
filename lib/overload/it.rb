# class Array
#   # list.xeach { it.foo }
#   def xeach &block
#     define_singleton_method(:it) { @_it } unless respond_to?(:it)
#     each do |_|
#       @_it = _
#       instance_eval &block
#     end
#   end

#   # list.xmap { it * 2 }
#   def xmap &block
#     define_singleton_method(:it) { @_it } unless respond_to?(:it)
#     map do |_|
#       @_it = _
#       instance_eval &block
#     end
#   end

#   # list.xselect { it.class != Module }
#   def xselect &block
#     define_singleton_method(:it) { @_it } unless respond_to?(:it)
#     select do |_|
#       @_it = _
#       instance_eval &block
#     end
#   end

# end
