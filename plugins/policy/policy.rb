# frozen_string_literal: true

# base caller
# Policy::User.new(model: @model, user: User.current).can?(:update) -> can current user update @model

# block will capture error message and will triggered only if error are present
# User.can?(:login) { |msg| http_error 401, "Err: #{msg}".red; return 'no access' }

class Policy
  attr_reader :model, :user, :action

  def initialize model:, user:
    @model = model
    @user  = user
  end

  # pass block if you want to handle errors yourself
  # return true if false if block is passed
  def can? action, &block
    @action = action
      .to_s
      .gsub(/[^\w+]/, '')
      .concat('?')
      .to_sym

    # pre check
    raise RuntimeError, 'Method name not allowed' if %i(can).index(@action)
    raise NoMethodError, %[Policy check "#{@action}" not found in #{self.class}] unless respond_to?(@action)

    call &block
  end

  # call has to be isolated because specific of error handling
  def call &block
    raise Error.new 'User is not defined' unless @user

    return true if before(@action)
    return true if send(@action)
    raise Error.new('Access disabled in policy')
   rescue Policy::Error => e
    error = e.message
    error += " - #{self.class}.#{@action}" if Lux.config(:dump_errors)

    if block
      block.call(error)
      false
    else
      raise Policy::Error.new(error)
    end
  end

  def proxy
    Proxy.new self
  end

  ###

  def before action
    false
  end

  def error message
    raise Policy::Error.new(message)
  end

end
