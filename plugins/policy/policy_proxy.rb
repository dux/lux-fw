# @object / nil
# @model.can.write?
#
# raise error or return @model
# @model.can.write!
#
# redirect on error or return true
# @model.can.write! { redirect_to '/login' }

class Policy
  class Proxy
    def initialize policy
      @policy = policy
    end

    def method_missing name, &block
      name   = name.to_s.sub(/(.)$/, '')
      action = $1

      if action == '!'
        @policy.can?(name, &block)
        @policy.model
      elsif action == '?'
        raise "Block given, not allowed in boolean (?) policy, use bang .#{name}! { .. }" if block_given?

        begin
          @policy.can?(name)
          @policy.model
        rescue Policy::Error
          yield if block_given?
          nil
        end
      else
        raise ArgumentError.new('Bad policy method name')
      end
    end
  end
end