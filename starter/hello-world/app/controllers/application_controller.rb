class ApplicationController < Lux::Controller
  layout :main
  helper :application

  before do
    @user = user

    # Exported to window.app.current.user, which app-nav.fez reads. The logout
    # link is built here because UserSession.logout_link needs the current user.
    lux.browser.window[:app][:current] = {
      user: @user && {
        ref:        @user.ref,
        email:      @user.email,
        name:       @user.name,
        logout_url: UserSession.logout_link
      }
    }
  end

  def login
    return redirect_to '/' if user

    redirect_to AuthcogController.auth_link
  end
end
