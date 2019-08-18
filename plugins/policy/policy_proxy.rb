# true / false
# @model.can.write?
#
# raise error or return true
# @model.can.write!
#
# redirect on error or return true
# @model.can.write! { redirect_to '/login' }

class Policy
  class Proxy
    def initialize object
      @object = object
    end

    def method_missing name, &block
      name   = name.to_s.sub(/(.)$/, '')
      action = $1

      if action == '!'
        @object.can?(name, &block)
        true
      elsif action == '?'
        raise 'Block given, not allowed in boolean policy' if block_given?

        begin
          @object.can?(name)
          true
        rescue Lux::Error
          yield if block_given?
          false
        end
      else
        raise ArgumentError.new('Bad policy method name')
      end
    end
  end
end