# class Foo
#   method_attr :name
#   method_attr :param do |field, type=String, opts={}|
#     opts[:name] = field
#     opts[:type] ||= String
#     opts
#   end

#   name "Test method desc"
#   param :email, :email
#   def test
#   end
# end

# ap Foo.method_attr
# {
#   "test": {
#     "name": [
#       "Test method desc"
#     ],
#     "param": [
#       {
#         "name": "email",
#         "type": "String"
#       }
#     ]
#   }
# }

module MethodAttributes
  extend self

  @@G_OPTS = {}
  @@M_OPTS = {}

  def define klass, param_name, &block
    klass.define_singleton_method(param_name) do |*args|
      @@M_OPTS[param_name] ||= []
      @@M_OPTS[param_name].push block ? block.call(*args) : args[0]
    end

    klass.define_singleton_method(:method_added) do |name|
      return unless @@M_OPTS.keys.first

      @@G_OPTS[to_s] ||= {}
      @@G_OPTS[to_s][name] = @@M_OPTS.dup
      @@M_OPTS.clear
    end
  end

  def get klass, method_name=nil
    return @@G_OPTS[klass.to_s] unless method_name

    klass.ancestors.map(&:to_s).each do |a_klass|
      v = @@G_OPTS[a_klass][method_name]
      return v if v
    end
  end
end

###

class Object
  def method_attr name=nil, &block
    return MethodAttributes.get(self).or({}) if name.nil?

    MethodAttributes.define self, name, &block
  end
end
