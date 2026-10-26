require_relative './policy'

module Lux
  class Policy
    class << self
      # try to load current user
      def current_user
        if Thread.current.key?(:current_user)
          Thread.current[:current_user]
        elsif defined?(::User) && ::User.respond_to?(:current)
          ::User.current
        elsif defined?(::Current) && ::Current.respond_to?(:user)
          ::Current.user
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

    # BasicObject, so actions named like Object predicates (present?, frozen?, ...)
    # still reach the policy
    class Proxy < ::BasicObject
      def initialize policy
        @policy = policy
      end

      # can.read? / can.read! - every predicate and bang form is answered
      def respond_to? name, include_private = false
        name.to_s.end_with?('?', '!')
      end

      def method_missing name, *args, &block
        name   = name.to_s
        action = name[-1]
        ::Kernel.raise ::NoMethodError, "undefined policy proxy method #{name}" unless action == '?' || action == '!'

        @policy.can?(name[0..-2], *args)
        action == '!' ? (@policy.model || true) : true
      rescue ::Lux::Policy::Error => error
        msg = block.call(error) if block
        ::Kernel.raise(msg ? ::Lux::Policy::Error.new(msg) : error) if action == '!'
        false
      end
    end
  end
end
