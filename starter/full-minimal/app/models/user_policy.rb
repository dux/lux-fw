class UserPolicy < Lux::Policy
  def admin?
    model.is_admin && !model.is_locked && !model.is_deleted
  end
end
