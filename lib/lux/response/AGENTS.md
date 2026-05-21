# Lux::Response - agent guide

Response builder. Available as `response` in controllers, `current.response`
elsewhere.

## Canonical example

```ruby
def show
  response.status 200
  response.header 'x-request-id', current.uid

  response.etag :report, Report.max(:updated_at)   # 304 + halt on match
  response.cache_public 10.minutes                 # opt-in public cache

  response.send_file './tmp/report.pdf', inline: true
end
```

## Rules

* **Setting body halts processing.** `response.body = '...'` or
  `response.body 'foo'` stops the action's render chain.
* **Default cache is PRIVATE.** No call needed. Public is opt-in via
  `cache_public N` or `response.cache.public = true`. Public cache
  **never** emits `Set-Cookie`.
* **Flash forces private** even if you set `cache.public`.
* **`response.no_store`** suppresses both cache and session cookie -
  use for sensitive responses (PII downloads, auth bounce pages).
* **ETag** is short-circuit: if the request's `If-None-Match` matches,
  Lux halts with 304 and the action does not render.
* **Content type:** symbols (`:json`, `:js`, `:plain`, `:xml`) resolve
  through Rack::Mime. Strings pass through.
* **`send_file` defaults to attachment.** Pass `inline: true` to render
  in the browser.
* **`redirect_to :back`** uses the Referer; falls back to `/`.
* **`halt status, body`** sets both and bails.

## Don't

* Don't set headers after `body=` - body-set halts the pipeline; later
  changes may not survive.
* Don't pass `Content-Type` in headers manually if you also set
  `content_type =` - use one path.
* Don't store binary blobs in flash - flash is cookie-backed.
* Don't bypass `response.send_file` with `File.read + body=` for large
  files - send_file streams.

## See also

* [`Lux::Current` AGENTS](../current/AGENTS.md)
* [`Lux::Error` AGENTS](../error/AGENTS.md) - error status helpers
