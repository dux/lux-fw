require_relative './error'

module Lux
  # Access policy class. Inherit and define question-mark methods.
  #
  #   class BlogPolicy < Lux::Policy
  #     def read?
  #       model.created_by == user.id
  #     end
  #   end
  #
  #   @blog.can.read?                # uses Lux::Policy.current_user
  #   @blog.can(@user).read!         # raises Lux::Policy::Error on false
  #   Lux::Policy.can(model: @blog).read?
  class Policy
    attr_reader :model, :user, :action

    def initialize model:, user: nil
      @model = model
      @user  = user || Lux::Policy.current_user
    end

    # pass block if you want to handle errors yourself
    # returns true / false if block is passed
    def can? action, *args, &block
      @action = action
        .to_s
        .gsub(/[^\w+]/, '')
        .concat('?')
        .to_sym

      # pre check
      if %i(can).index(@action)
        raise RuntimeError.new('Method name not allowed')
      end

      unless respond_to?(@action)
        raise NoMethodError.new(%[Policy check "#{@action}" not found in #{self.class}])
      end

      call *args, &block
    end

    def can
      Proxy.new self
    end

    private

    # call has to be isolated because of specifics in handling
    def call *args, &block
      return true if before(@action) == true
      return true if send(@action, *args)

      error 'Access disabled in policy'
    rescue Lux::Policy::Error => error
      message = error.message
      message += " - #{self.class}##{@action}"

      if block
        block.call message
        false
      else
        error message
      end
    end

    def before action
      false
    end
  end
end
