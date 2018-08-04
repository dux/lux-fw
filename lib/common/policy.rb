# frozen_string_literal: true

# base caller
# UserPolicy.new(model: @model, user: User.current).can?(:update) -> can current user update @user
# ApplicationPolicy.new(user: Lux.current.var.user).can?(:admin_login?) -> can current user login to admin

# block will capture error message and be triggered only if error is present
# User.can?(:login) { |msg| http_error 401, "Err: #{msg}".red; return 'no access' }

class Policy

  def initialize hash
    for k, v in hash
      instance_variable_set "@#{k}", v
    end
  end

  # pass block if you want to handle errors yourself
  # return true if false if block is passed
  def can? action, &block
    @action = action.to_s.sub('?','') + '?'
    @action = @action.to_sym

    # pre check
    raise RuntimeError, 'Method name not allowed' if %w(can).index(@action)
    raise NoMethodError, %[Policy check "#{action}" not found in #{self.class}] unless respond_to?(@action)

    call &block
  end

  # call has to be isolated because specific of error handling
  def call &block
    return true if before(@action)
    return true if send(@action)
    raise Lux::Error.unauthorized('Access disabled in policy')
   rescue Lux::Error
    error = $!.message
    error += " - #{self.class}.#{@action}" if Lux.config(:show_server_errors)
    raise Lux::Error.unauthorized(error) unless block
    block.call(error)
    false
  end

  ###

  def before action
    false
  end

  def error message
    raise Lux::Error.unauthorized(message)
  end

end
