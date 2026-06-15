class DevController < FrontendController
  layout :dev
  helper :html

  before do
    nav.path.shift
  end

  route '/dev/login'
  allow :post
  def login
    UserSession.login_user_ref params.user_ref
    redirect_to '/dev/login_as'
  end
end
