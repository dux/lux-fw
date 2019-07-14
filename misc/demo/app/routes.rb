Lux.app do

  # define proc for dinamic routes
  namespace :city do
    if ['zagreb', 'munich'].include?(nav.root)
      @city = nav.root.capitalize
    else
      false
    end
  end

  routes do
    root 'main/root#index'

    # call action in a controller
    map text: 'main/root#text'

    # plain text namespace
    # /foo/bar
    namespace 'foo' do
      root     proc { response 'foo root OK' }
      map bar: proc { response 'foo/bar match OK' }
    end

    # dynamic rooute call demo
    # /zabreb/foo
    # /munich/foo
    namespace :city do
      root     proc { response 'City %s root OK' % @city }
      map foo: proc { response 'foo/bar match in %s OK' % @city }
    end
  end

  # after routing
  after do
    # not found route
    call 'main/base#not_found' unless body?
    # response 'Error: document not found', 404 unless body?
  end

end