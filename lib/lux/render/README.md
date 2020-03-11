## Lux.render

Render full pages.

As a first argument to any render method you can provide
full [Rack environment](https://www.rubydoc.info/gems/rack/Rack/Request/Env).

If you provide only local path,
[`Rack::MockRequest`](https://www.rubydoc.info/gems/rack/Rack/MockRequest) will be created.

Two ways of creating render pages are provided.

* full builder `Lux.render(@path, @full_opts)`
* helper builder with request method as method name `Lux.render.post(@path, @params_hash, @rest_of_opts)`

```ruby
# opts options
opts = {
  query_string: {}
  post: {},
  body: String
  request_method: String
  session: {}
  cookies: {}
}

page = Lux.render('/about', opts)
page = Lux.render.post('/api/v1/orgs/list', { page_size: 100 }, rest_of_opts)
page = Lux.render.get('/search', { q: 'london' }, { session: {user_id: 1} })

page.info
# render info CleanHash
# {
#   body:    '{}',
#   time:    '5ms',
#   status:  200,
#   session: { user_id: 123 }
#   headers: { ... }
# }

page.render # get only body
```
