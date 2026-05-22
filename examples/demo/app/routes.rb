Lux.app do

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

    # namespace route demo
    # /city/foo
    map 'city' do
      root     proc { body = 'City root OK' }
      map foo: proc { body = 'city/foo match OK' }
    end
  end

  # after routing
  after do
    # not found route
    call 'main/base#not_found' unless body?
    # response 'Error: document not found', 404 unless body?
  end

end