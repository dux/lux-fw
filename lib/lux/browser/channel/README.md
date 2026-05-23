# Lux::Browser::Channel

In-process pub/sub channels by name. Backbone for the SSE streams
served by `response.sse`. Publish from anywhere; subscribe via a
controller action; react on the client.

Nested under `Lux::Browser` because the only consumer today is the
SSE writer (`response/lib/sse.rb`) which fans messages out to the
`window.Lux.sse` client module served by `Lux::Browser`.

## Full example

```ruby
# --- publish from anywhere (jobs, callbacks, actions, defer'd threads) ---

Lux.channel(:notifications).push(message: 'Hello')
Lux.channel("user:#{user.id}").push(type: :inbox, count: 3)

# Strings, hashes, arrays, numbers - anything JSON-serialisable. Strings pass
# through verbatim; everything else is JSON.generate-d before sending.

# --- subscribe via a controller (the only normal way to subscribe) ---

class StreamController < Lux::Controller
  def show
    Lux.error.unauthorized unless current_user
    # Channel names come from server-trusted sources; never from params.
    response.sse :notifications, "user:#{current_user.id}"
  end
end

# --- client (delivered by Lux::Browser, served at /lux/client.js) ---
#
#   <script src="/lux/client.js"></script>
#   <script>
#     Lux.sse.on('notifications', msg => banner.show(msg))
#     Lux.sse.on('user:42',       msg => inbox.update(msg))
#     Lux.sse.connect('/stream')
#   </script>

# --- diagnostics ---

Lux::Browser::Channel.channels                       # ["notifications", "user:42"]
Lux::Browser::Channel.subscriber_count(:notifications)  # int

Lux::Browser::Channel.reset!                         # drop every subscriber (tests only)
```

`Lux::Browser::Channel.subscribe(name, queue)` / `Lux::Browser::Channel.unsubscribe(name, queue)`
are internal - used by `response.sse` to attach and detach a queue per
client. Do not call from app code; subscribe by mounting an SSE endpoint
and letting the framework drive the lifecycle.

## How it works

* `Lux::Browser::Channel` keeps a `name -> [Queue, ...]` registry guarded by a Mutex.
* `Lux.channel(name).push(data)` fans `data` out to every queue currently
  subscribed to `name`.
* `response.sse(*channels)` opens a `text/event-stream` response, attaches
  a queue to each channel, yields formatted SSE frames until the client
  disconnects, and detaches in `ensure`.
* The client (`Lux.sse`) opens one `EventSource` per page; events are
  tagged with the channel name and dispatched to per-channel listeners.

## Heartbeats and disconnects

The server emits `: ping\n\n` every 30 seconds so proxies don't reap idle
connections. Client disconnects raise `IOError` / `EPIPE` / `ECONNRESET`
inside the SSE writer; the subscription is closed in an `ensure` block.

## Limitations

* **In-process only.** Publish in worker A does not reach subscribers in
  worker B. Use a single-process server (Falcon), sticky routing, or wait
  for the planned PG `LISTEN/NOTIFY` broker (mirroring `plugins/job_runner`).
* **No replay.** Subscribers see only what is published after they connect;
  the framework does not buffer.

## API

| call | returns | notes |
|------|---------|-------|
| `Lux.channel(name).push(data)` | nil | broadcast to all subscribers of `name` |
| `Lux::Browser::Channel.channels` | `[String]` | active channel names |
| `Lux::Browser::Channel.subscriber_count(name)` | Integer | |
| `Lux::Browser::Channel.reset!` | nil | drop every subscriber (tests only) |
| `Lux::Browser::Channel.subscribe / .unsubscribe` | | **internal** - driven by `response.sse` |

## See also

* [`../../response/lib/sse.rb`](../../response/lib/sse.rb) - the SSE writer (`response.sse`)
* [`../README.md`](../README.md) - parent `Lux::Browser` (serves the `Lux.sse` client)
* [`../../../../plugins/job_runner/README.md`](../../../../plugins/job_runner/README.md) - PG LISTEN/NOTIFY pattern
