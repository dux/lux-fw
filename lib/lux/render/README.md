# Lux::Render

Render full pages, controllers, templates, and view cells - from
production code (server-rendered HTML in a job, mailer body, etc.) or
from tests / scripts.

`Lux.render` returns the render namespace; the shortcuts below dispatch
HTTP-shaped renders (`get`/`post`/...) and lower-level renders
(`controller`/`template`/`cell`).

## Full example

```ruby
# --- full-page render (drives Lux.app like a real HTTP request) --------

page = Lux.render.get('/about')
page.body                          # body string
page.status                        # HTTP code
page.headers                       # response headers
page.session                       # post-request session
page.time                          # '5ms'

page = Lux.render.get('/search',
  query_string: { q: 'london' },
  session:      { user_id: 1 }
)
page = Lux.render.post('/api/v1/users/create', post: { name: 'Dux' })
page = Lux.render.delete('/api/v1/users/123', session: { user_id: 1 })

# authenticate as a user via bearer token (shortcut for the Authorization header)
page = Lux.render.get('/dashboard', bearer: 'rejotl@gmail.com')

# accepted opts:
#   method:        :get / :post / :put / :patch / :delete  (set by the shortcut)
#   params:        shorthand for query_string (get) or post (others)
#   query_string:  hash, added to URL
#   post:          hash, POST body
#   body:          raw string body
#   session:       initial session contents
#   cookies:       initial cookies
#   headers:       hash, request headers ('Authorization' => ..., mapped to HTTP_*)
#   bearer:        string, shortcut for headers: { 'Authorization' => "Bearer <token>" }

# --- controller render (skips routing, runs the controller directly) ---

Lux.render.controller('main/cities#foo').body
Lux.render.controller('main/cities#bar') { @city = City.last_updated }.body

# --- template render (Tilt-based) --------------------------------------

Lux.render.template(self, './app/views/mailer/welcome.haml')
Lux.render.template(self, template: 'a.haml', layout: 'b.haml')
Lux.render.template(scope, './layout.haml') { 'inner content' }

# --- view cell render --------------------------------------------------

Lux.render.cell(:user, self, product: @bar).in_a_box   # UserCell.new(self, product: @bar).in_a_box
Lux.render.cell(:user).in_a_box(@user)                  # UserCell.new.in_a_box(@user)

# --- helper builder (for use outside a template / controller) ----------

helper = Lux::Template.helper(self.instance_variables_hash, :html, :main)
helper.link_to 'Home', '/'
```

## CLI

```bash
lux render /about                            # render and print body
lux render /search -p q=london               # with params
lux render /api/users/show -m post -t TOKEN  # POST with bearer
lux render /admin -s user_id=1 -i            # session + full info hash
```

## Page `<head>` builder

`Lux::Render::Header` is the per-request `<head>` builder, reached as
`lux.header` (memoized on `Lux.current`). Chain-set title / meta / links,
then emit via `lux.header.render` in the layout's `%head` block.

```ruby
lux.header.title       'My page'
lux.header.description 'short summary'
lux.header.canonical   'https://example.com/page'
```

```haml
%head
  = lux.header.render do |page|
    = asset 'main.css'
```

## See also

* [`../template/README.md`](../template/README.md) - the template engine
* [`../view_cell/README.md`](../view_cell/README.md) - reusable view components
* [`../controller/README.md`](../controller/README.md) - controllers
