Lux.app do
  before do
    UserSession.resolve
    UserSession.destroy_session if user && (user.is_locked || user.is_deleted)
  end

  routes do
    map '/authcog', 'authcog#call'
    map '/login', 'promo#login'

    map 'app' do
      root 'main'
    end

    map 'admin' do
      root 'admin'
    end

    root 'promo'
  end
end
