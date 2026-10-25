class MainRouter < FrontendRouter
  before do
    unless user
      UserSession.redirect_after_login = request.path
      redirect_to '/login'
    end
  end

  def index
  end
end
