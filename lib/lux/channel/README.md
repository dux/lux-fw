# Lux::Channel

In-process pub/sub channels by name. Backbone for the SSE streams
served by `response.sse`. Publish from anywhere, subscribe via a
controller action, react on the client.

## Small example

```ruby
# Publish from anywhere
Lux.channel(:notifications).push(message: 'Hello')
Lux.channel("user:#{user.id}").push(type: :inbox, count: 3)
```

```ruby
# Subscribe via a controller
class StreamController < Lux::Controller
  def show
    Lux.error.unauthorized unless current_user
    response.sse :notifications, "user:#{current_user.id}"
  end
end
```

```html
<!-- Client -->
<script src="/lux/client.js"></script>
<script>
  Lux.sse.on('notifications', msg => banner.show(msg))
  Lux.sse.on('user:42',       msg => inbox.update(msg))
  Lux.sse.connect('/stream')
</script>
```

## How it works

* `Lux::Channel` keeps a `name -> [Queue, ...]` registry guarded by a
  Mutex.
* `Lux.channel(name).push(data)` fans `data` out to every queue
  currently subscribed to `name`.
* `response.sse(*channels)` opens a `text/event-stream` response,
  attaches a `Queue` to each channel, and yields formatted SSE frames
  until the client disconnects.
* The client (`Lux.sse`) opens one `EventSource` per page; events are
  tagged with the channel name and dispatched to per-channel listeners.

## Authorization

`response.sse` runs inside a normal controller action. Auth, policy
checks, and channel-name construction are the app's responsibility:

```ruby
def stream
  Lux.error.unauthorized unless current_user
  response.sse "user:#{current_user.id}"   # never accept channel from params
end
```

## Heartbeats and disconnects

The server emits `: ping\n\n` every 30 seconds so proxies don't reap
the idle connection. Client disconnects raise `IOError` / `EPIPE` /
`ECONNRESET` inside the SSE writer; the subscription is closed in an
`ensure` block.

## Message format

* `data` may be any JSON-serialisable value (Hash, Array, String,
  Number). Strings pass through verbatim; everything else is
  `JSON.generate`-d before sending.
* The client auto-parses JSON; failures fall back to the raw string.

## Limitations

* **In-process only.** Publish from worker A does not reach
  subscribers on worker B. For multi-worker deployments use a
  single-process server (Falcon), sticky routing, or wait for the
  follow-up PG `LISTEN/NOTIFY` broker (modelled on `plugins/job_runner`).
* **No replay.** EventSource auto-reconnects on the client, but the
  server does not buffer past messages. Subscribers see only what is
  published after they connect.

## API

| call | notes |
|------|-------|
| `Lux.channel(name).push(data)` | broadcast `data` to all subscribers |
| `Lux::Channel.subscribe(name, queue)` | attach `queue`; returns `Subscription` |
| `Lux::Channel.unsubscribe(name, queue)` | detach |
| `Lux::Channel.channels` | currently-active channel names |
| `Lux::Channel.subscriber_count(name)` | int |
| `Lux::Channel.reset!` | drop everything (tests only) |

## See also

* [`AGENTS.md`](./AGENTS.md) - LLM guide
* [`../response/lib/sse.rb`](../response/lib/sse.rb) - the SSE writer
* [`../browser/README.md`](../browser/README.md) - serves `Lux.sse` to the client
* [`../../../plugins/job_runner/README.md`](../../../plugins/job_runner/README.md) - similar PG LISTEN/NOTIFY pattern
