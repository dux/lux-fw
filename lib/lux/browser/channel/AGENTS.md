# Lux::Browser::Channel - agent guide

In-process pub/sub channels backing the SSE streams served by
`response.sse`. **Publish anywhere, subscribe inside a controller
action that calls `response.sse(*names)`; client receives events
tagged by channel name via `Lux.sse.on`.**

## Canonical example

```ruby
# server: publish from anywhere
Lux.channel(:notifications).push(message: 'Hello')
Lux.channel("user:#{user.id}").push(type: :inbox, count: 3)

# server: subscribe a client via a controller action
class StreamController < Lux::Controller
  def show
    Lux.error.unauthorized unless current_user
    # Channel names come from server-trusted sources, never request params.
    response.sse :notifications, "user:#{current_user.id}"
  end
end
```

```html
<!-- client (composed by Lux::Browser, served at /lux/client.js) -->
<script src="/lux/client.js"></script>
<script>
  Lux.sse.on('notifications', msg => banner.show(msg))
  Lux.sse.on('user:42',       msg => inbox.update(msg))
  Lux.sse.connect('/stream')
</script>
```

## Rules

* **Channel names are server-trusted strings.** Never construct a
  subscribe-side channel name from request params - that lets a caller
  listen to any channel by guessing the name. Build it from
  `current_user.id` / scoped record refs.
* **Message data is JSON-serialised** when not a String. Keep payloads
  small; SSE has no chunk negotiation.
* **Subscribe lifecycle is automatic.** `response.sse` attaches the
  subscription, drives the writer, and detaches in an ensure block on
  client disconnect.
* **In-process only.** Cross-worker fan-out is a follow-up (PG
  LISTEN/NOTIFY, same shape as `plugins/job_runner`). Until then,
  single-process servers (Falcon) or sticky routing are the deploy
  targets.
* **30-second heartbeats** (`: ping\n\n`) are emitted automatically to
  keep proxies from reaping the idle connection.

## Don't

* Don't pass user-supplied channel names into `response.sse`.
* Don't use `Lux::Browser::Channel` as a job queue - there's no persistence,
  retries, or delivery guarantees. Use `plugins/job_runner` for that.
* Don't push large payloads (megabytes). SSE is for small frequent
  events; for big things send a notification + a fetch URL.
* Don't subscribe from outside a controller action (no `response.sse`
  caller) unless you're writing a test - use the `Lux::Browser::Channel.subscribe`
  primitive only when you have a clear lifetime to close the subscription.

## See also

* [`README.md`](./README.md) - human-facing API reference
* [`../../response/lib/sse.rb`](../../response/lib/sse.rb) - the SSE writer
* [`../AGENTS.md`](../AGENTS.md) - parent `Lux::Browser` (serves the `Lux.sse` client module)
