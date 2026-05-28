class ApplicationController < Lux::Controller
  layout :main

  before do
    # restore the signed-in user from the session
    if (ref = session[:user_ref])
      User.current = User[ref]
    end
  end

  def user
    User.current
  end
end
