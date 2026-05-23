# Lux::Response

HTTP response builder. Use as `response` inside a controller, or
`current.response` anywhere.

## Full example

```ruby
class FilesController < ApplicationController
  def show
    # --- status / headers ----------------------------------------------
    response.status 200                           # also: response.status = 200
    response.header 'x-app', 'lux'                # also: response.headers['x-app']

    # --- content type -------------------------------------------------
    response.content_type = :json                 # :json / :js / :plain / :xml / mime string

    # --- body ---------------------------------------------------------
    response.body 'hello'                         # also: response.body = '...'
    response.body { |old| transform(old) }        # transform existing body
    response.body?                                # true if a body is set

    # --- caching ------------------------------------------------------
    # default is private, must-revalidate, max-age=0; public is opt-in.
    response.cache_public 10.minutes              # shortcut
    response.cache.public  = true
    response.cache.max_age = 10.minutes
    response.cache.stale_while_revalidate = 1.hour
    response.no_store                             # disables cache + Set-Cookie

    # --- etag (returns 304 + halts on If-None-Match match) ------------
    response.etag :report, Report.max(:updated_at)

    # --- file download / inline ---------------------------------------
    response.send_file './tmp/report.pdf'                   # download
    response.send_file './tmp/report.pdf', inline: true     # render in browser
    response.send_file path, name: 'Invoice-2026.pdf'       # custom filename

    # --- redirect (flash-aware) ----------------------------------------
    response.redirect_to '/foo'
    response.redirect_to '/foo', info: 'Moved'
    response.redirect_to :back, error: 'Invalid'
    response.permanent_redirect_to '/new-home'    # 301

    # --- flash --------------------------------------------------------
    response.flash.info    'Saved'
    response.flash.error   'Bad password'
    response.flash.warning 'Disk almost full'

    # --- halt with status + body --------------------------------------
    response.halt 422, { errors: { name: 'is required' } }.to_json

    # --- HTTP early hints / basic auth --------------------------------
    response.early_hints '/app.css', :stylesheet
    response.auth(realm: 'admin') do |user, pass|
      [user, pass] == ['root', ENV['ADMIN_PASS']]
    end

    # --- CORS (see Lux::Response::Cors) -------------------------------
    response.cors :all                            # permissive
    response.cors origins: %w[https://app.example.com],
                  methods: %i[get post],
                  headers: %w[Authorization Content-Type],
                  credentials: true,
                  max_age: 600

    # --- SSE stream (see Lux::Response::Sse + Lux::Browser::Channel) --
    response.sse :notifications, "user:#{current_user.id}"

    # --- generic streaming body ---------------------------------------
    response.stream(MyIterableBody.new)           # body responds to .each(yields strings)
    response.streaming?                           # true after .sse / .stream

    # --- dispatch to a mounted Rack app -------------------------------
    response.rack RackApp, mount_at: '/api'
  end
end
```

## Cache rules

* Default: **private, must-revalidate, max-age=0**.
* Public cache never emits `Set-Cookie`.
* Any flash forces private.
* `no_store` suppresses cache + session cookie (use for sensitive responses).

## Flash

Set before a redirect; the next response receives the entries. Setting
any flash forces the response private.

## Streaming responses

`response.sse(*channels)` and `response.stream(body)` both set a
streaming body. The render path:

* skips body text-classification and JSON serialisation
* skips `Content-Length` (body is iterated)
* skips automatic ETag (body would have to be hashed first)
* returns the body directly to Rack (it must respond to `.each` yielding strings)

## See also

* [`./lib/cors.rb`](./lib/cors.rb) - the `response.cors` implementation
* [`./lib/sse.rb`](./lib/sse.rb) - the `response.sse` SSE writer
* [`../browser/channel/README.md`](../browser/channel/README.md) - pub/sub channels feeding SSE
* [`../current/README.md`](../current/README.md) - request context
* [`AGENTS.md`](./AGENTS.md) - LLM guide
