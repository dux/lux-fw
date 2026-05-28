Lux.app do
  routes do
    # central-auth login callback
    map 'authcog', 'authcog#call'

    map logout: 'main#logout'

    root 'main'
  end
end
