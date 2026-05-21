# Lux::Render

Render full pages, controllers, templates, and view cells - either from
production code (server-rendered HTML in a job, mailer body, etc.) or
from tests / scripts.

## Small example

```ruby
# render a page like a real HTTP request, no server needed
page = Lux.render.get('/about')
page.body                          # body string
page.status                        # HTTP code
page.headers                       # response headers

# render a controller action directly
Lux.render.controller('users#show') { @user = User.first }.body
```

## Full example

```ruby
# --- full-page render (uses Lux.app router internally) -------------------

page = Lux.render.get('/search', query_string: { q: 'london' }, session: { user_id: 1 })
page = Lux.render.post('/api/v1/users/create', post: { name: 'Dux' })
page = Lux.render.delete('/api/v1/users/123', session: { user_id: 1 })

# returns a hash:
# {
#   body:    '...',
#   status:  200,
#   headers: { ... },
#   session: { user_id: 1 },     # post-request session
#   time:    '5ms'
# }

# --- controller render (skips routing, runs the controller directly) -----

Lux.render.controller('main/cities#foo').body
Lux.render.controller('main/cities#bar') { @city = City.last_updated }.body

# --- template render (Tilt-based) ----------------------------------------

Lux.render.template(self, './app/views/mailer/welcome.haml')
Lux.render.template(self, template: 'a.haml', layout: 'b.haml')
Lux.render.template(scope, './layout.haml') { 'inner content' }

# --- helper builder ------------------------------------------------------

helper = Lux::Template.helper(self.instance_variables_hash, :html, :main)
helper.link_to 'Home', '/'

# --- view cell render ----------------------------------------------------

# UserCell.new(self, product: @bar).in_a_box  ->
Lux.render.cell(:user, self, product: @bar).in_a_box

# UserCell.new.in_a_box(@user)  ->
Lux.render.cell(:user).in_a_box @user
```

## Per-request render options

`Lux.render.<method>(path, opts)` accepts:

| Key | Type | Notes |
|-----|------|-------|
| `method`        | sym/str | `:get`, `:post`, `:put`, `:patch`, `:delete` (set by the shortcut) |
| `params`        | hash | shorthand for query_string (get) or post (others) |
| `query_string`  | hash | added to URL |
| `post`          | hash | POST body |
| `body`          | string | raw body |
| `session`       | hash | initial session contents |
| `cookies`       | hash | initial cookies |
| `headers`       | hash | env-style (HTTP_AUTHORIZATION etc.) |

## CLI

```bash
lux render /about                            # render and print body
lux render /search -p q=london               # with params
lux render /api/users/show -m post -t TOKEN  # POST with bearer
lux render /admin -s user_id=1 -i            # session + full info hash
```

## See also

* [`../template/README.md`](../template/README.md) - the template engine
* [`../view_cell/README.md`](../view_cell/README.md) - reusable view components
* [`../controller/README.md`](../controller/README.md) - controllers
* [`AGENTS.md`](./AGENTS.md) - LLM guide
