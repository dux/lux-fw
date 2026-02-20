Lux.app do

  # define proc for dinamic routes
  def city_map
    if ['zagreb', 'munich'].include?(nav.root)
      @city = nav.root.capitalize
    else
      false
    end
  end

  routes do
    call 'application#on_error'

    root 'main/root#index'

    # call action in a controller
    map text: 'main/root#text'

    # plain text namespace
    # /foo/bar
    map 'foo' do
      root     proc { body = 'foo root OK' }
      map bar: proc { body = 'foo/bar match OK' }
    end

    # dynamic rooute call demo
    # /zabreb/foo
    # /munich/foo
    map :city do
      root     proc { body = 'City %s root OK' % @city }
      map foo: proc { body = 'foo/bar match in %s OK' % @city }
    end
  end

  # after routing
  after do
    # not found route
    call 'main/base#not_found' unless body?
    # response 'Error: document not found', 404 unless body?
  end

end