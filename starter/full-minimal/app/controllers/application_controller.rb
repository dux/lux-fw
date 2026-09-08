class ApplicationController < Lux::Controller
  layout :main
  helper :application

  before do
    @user = user
  end

  def login
    return redirect_to '/' if user

    redirect_to AuthcogController.auth_link
  end
end
