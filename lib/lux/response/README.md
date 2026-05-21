# Lux::Response

HTTP response builder. Use as `response` inside a controller, or
`current.response` anywhere.

## Small example

```ruby
response.status = 201
response.header 'x-request-id', current.uid
response.body = { ok: true }.to_json
```

## Full example

```ruby
class FilesController < ApplicationController
  def show
    # status + headers
    response.status 200
    response.header 'x-app', 'lux'

    # caching: default is private/uncached - public is opt-in
    response.cache_public 10.minutes
    response.cache.stale_while_revalidate 1.hour

    # ETag (returns 304 + halts on If-None-Match match)
    response.etag :report, Report.max(:updated_at)

    # set body (halts further processing)
    response.body 'hello'
    response.content_type = :json

    # file download / inline
    response.send_file './tmp/report.pdf', inline: true

    # halt with a status + body
    response.halt 422, { errors: { name: 'is required' } }.to_json

    # redirect (flash-aware)
    response.redirect_to '/login', error: 'Session expired'
    response.permanent_redirect_to '/new-home'    # 301

    # HTTP early hints
    response.early_hints '/app.css', :stylesheet

    # basic HTTP auth
    response.auth(realm: 'admin') do |user, pass|
      [user, pass] == ['root', ENV['ADMIN_PASS']]
    end
  end
end
```

## Status / headers / body

```ruby
response.status          # get
response.status = 400    # set
response.status 400      # set (alt)

response.header                  # full hash
response.header 'x-foo', 1       # set
response.headers['x-foo']        # alias

response.content_type            # get
response.content_type = :json    # set (or :js, :plain, :xml, mime string)

response.body                    # get
response.body 'foo'              # set
response.body = 'foo'            # set
response.body?                   # true if body present
response.body { |old| transform(old) }   # transform in place
```

## Cache control

Default is **private, must-revalidate, max-age=0** - no caller action
required. Public cache is opt-in.

```ruby
response.cache_public 10.minutes                 # shortcut for shared cache
response.cache.public = true
response.cache.max_age = 10.minutes
response.cache.stale_while_revalidate = 1.hour
response.no_store                                # disables cache + cookie
```

Rules:

* Public cache never emits `Set-Cookie`.
* Flash messages force private.
* `no_store` suppresses cache + session cookie (use for sensitive responses).

## Flash

```ruby
response.flash.info  'Saved'
response.flash.error 'Bad password'
response.flash.warning 'Disk almost full'
```

Set before a redirect; the next response receives them. Setting any flash
forces the response private.

## File and data

```ruby
response.send_file './path.pdf'                          # forces download
response.send_file './path.pdf', inline: true            # render in browser
response.send_file path, name: 'Invoice-2026.pdf'        # custom filename
```

## Redirect

```ruby
response.redirect_to '/foo'
response.redirect_to '/foo', info: 'Moved'
response.redirect_to :back, error: 'Invalid'
response.permanent_redirect_to '/new-home'               # 301
```

## Halt and rack mount

```ruby
response.halt 422, { errors: {} }.to_json    # set status + body, deliver
response.rack RackApp, mount_at: '/api'      # dispatch to mounted Rack app
```

## See also

* [`../current/README.md`](../current/README.md) - request context
* [`AGENTS.md`](./AGENTS.md) - LLM guide
