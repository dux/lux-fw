class AdminController < MainController
  views :admin

  before do
    next if @error

    raise Lux.error.forbidden('Admin access required') unless user.can.admin?
  end

  def root
    @user_count = User.count
  end
end
