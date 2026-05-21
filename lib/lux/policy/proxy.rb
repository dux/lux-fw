require_relative './policy'

module Lux
  class Policy
    class << self
      # try to load current user
      def current_user
        if Thread.current.key?(:current_user)
          Thread.current[:current_user]
        elsif defined?(User) && User.respond_to?(:current)
          User.current
        elsif defined?(Current) && Current.respond_to?(:user)
          Current.user
        else
          raise RuntimeError.new('Current user not found in Lux::Policy#current_user')
        end
      end

      def can model = nil, user = nil
        if model.is_hash?
          model, user = model[:model], model[:user]
        end

        klass = self

        # if we are calling can on Lux::Policy class, figure out policy class
        if self == Lux::Policy
          klass = ('%s_policy' % model.class).classify
          klass = Object.const_defined?('::%s' % klass) ? klass.constantize : raise('Policy class %s not defined' % klass)
        end

        klass.new(user: user, model: model).can
      end
    end

    class Proxy
      def initialize policy
        @policy = policy
      end

      def method_missing name, *args, &block
        name   = name.to_s.sub(/(.)$/, '')
        action = $1

        @policy.can?(name, *args)

        if action == '!'
          @policy.model || true
        else
          true
        end
      rescue Lux::Policy::Error => error
        msg = yield error if block_given?

        if action == '!'
          raise msg ? Lux::Policy::Error.new(msg) : error
        elsif action == '?'
          false
        else
          raise ArgumentError.new('Bad policy method %s' % name)
        end
      end
    end
  end
end
