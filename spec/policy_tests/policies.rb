class PolApplicationPolicy < Lux::Policy
  def before action
    return true if action == :before_1?
  end

  def admin?
    @user.is_admin
  end

  def before_1?
    raise 'abc'
  end

  def before_2?
    false
  end

  def before_3?
    true
  end

  def before_4?
    true
  end

  def custom_error?
    error 'foo'
  end
end

class PolPostPolicy < Lux::Policy
  def write?
    @user.is_admin || @user.id == @model.created_by
  end

  def create? opts = {}
    opts[:ip] == '1.2.3.4'
  end
end

class PolHeadlessPolicy < Lux::Policy
  def read?
    true
  end
end
