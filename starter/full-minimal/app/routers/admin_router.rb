class AdminRouter < MainRouter
  views :admin

  before do
    raise Lux.error.forbidden('Admin access required') unless user.can.admin?
  end

  def index
    @user_count = User.count
  end
end
