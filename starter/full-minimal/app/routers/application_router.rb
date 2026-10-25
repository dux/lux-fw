class ApplicationRouter < Lux::Router
  layout :main
  helper :application

  before do
    @user = user
  end

  def login
    return redirect_to '/' if user

    redirect_to AuthcogRouter.auth_link
  end
end
