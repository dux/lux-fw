Lux.app do

  routes do
    root 'main/root#index'

    # call action in a controller
    map text: 'main/root#text'

    # markdown view demo (renders app/views/main/root/markdown.md)
    map markdown: 'main/root#markdown'

    # plain text namespace
    # /foo/bar
    map 'foo' do
      root     proc { 'foo root OK' }
      map bar: proc { 'foo/bar match OK' }
    end

    # namespace route demo
    # /city/foo
    map 'city' do
      root     proc { 'City root OK' }
      map foo: proc { 'city/foo match OK' }
    end

    # nothing matched - the last routes statement is the 404
    body 'Error: document not found', status: 404
  end

end
