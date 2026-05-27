# Lux::Browser::Channel

In-process pub/sub channels by name. Backbone for the SSE streams
served at the baked-in `/_lux_/stream` endpoint. Publish from anywhere on
the server with `Lux.browser.publish`; subscribe from the client with
`Lux.subscribe`.

Nested under `Lux::Browser` because the only consumer today is the
SSE writer (`response/lib/sse.rb`) which fans messages out to the
`Lux.subscribe` client module served at `/_lux_/client.js`.

## Full example

```ruby
# --- publish from anywhere (jobs, callbacks, actions, defer'd threads) ---

Lux.browser.publish :notifications, message: 'Hello'
Lux.browser.publish "user:#{user.id}", type: :inbox, count: 3

# Strings, hashes, arrays, numbers - anything JSON-serialisable. Strings pass
# through verbatim; everything else is JSON.generate-d before sending.
```

```html
<!-- client: just include /_lux_/client.js and call subscribe -->
<script src="/_lux_/client.js"></script>
<script>
  Lux.subscribe('notifications', msg => banner.show(msg))
  Lux.subscribe('user:42',       msg => inbox.update(msg))
  // auto-connects to /_lux_/stream on first subscribe;
  // subscribing to a new channel reopens with the merged list (debounced).

  Lux.unsubscribe('notifications', fn)   // drop one handler
  Lux.unsubscribe('notifications')       // drop the channel entirely
  Lux.disconnect()                       // close the stream
</script>
```

```ruby
# --- diagnostics ---

Lux::Browser::Channel.channels                          # ["notifications", "user:42"]
Lux::Browser::Channel.subscriber_count(:notifications)  # int
Lux::Browser::Channel.reset!                            # drop every subscriber (tests only)
```

## Endpoint

The framework intercepts `/_lux_/stream?channels=a,b,c` and streams the
SSE feed for those channels. **No authorization is enforced here** - the
client can request any channel name. Gate access at your edge (front
proxy / WAF) or with a global before-filter in `Lux::Application` that
rewrites or rejects the request before it reaches `Lux::Browser::Mount`.

`response.sse(*channels)` still exists for app-defined SSE endpoints,
but for the standard publish/subscribe surface you no longer need a
custom controller.

`Lux::Browser::Channel.subscribe(name, queue)` /
`Lux::Browser::Channel.unsubscribe(name, queue)` are internal - used by
the SSE writer to attach and detach a queue per client.

## How it works

* `Lux::Browser::Channel` keeps a `name -> [Queue, ...]` registry guarded by a Mutex.
* `Lux.browser.publish(name, data)` fans `data` out to every queue currently
  subscribed to `name` (or, with the broker on, via PG NOTIFY).
* `/_lux_/stream` opens a `text/event-stream` response, attaches a queue
  to each requested channel, yields formatted SSE frames until the client
  disconnects, and detaches in `ensure`.
* The client (`Lux.subscribe`) opens one `EventSource` per page; events
  are tagged with the channel name and dispatched to per-channel listeners.

## Heartbeats and disconnects

The server emits `: ping\n\n` every 30 seconds so proxies don't reap idle
connections. Client disconnects raise `IOError` / `EPIPE` / `ECONNRESET`
inside the SSE writer; the subscription is closed in an `ensure` block.

## Limitations

* **In-process by default.** A publish in worker A does not reach subscribers
  in worker B unless the PG broker is started (see below).
* **No replay.** Subscribers see only what is published after they connect;
  the framework does not buffer.

## Cross-process: PG LISTEN/NOTIFY

Two switches, both off by default:

* `pg_publish!` - route `Channel.publish` through `NOTIFY` instead of the
  in-process queue. Use in processes that only publish (job runners, rake
  tasks, scripts).
* `pg_listen!` - also start a dedicated background thread that holds a
  PG connection in `LISTEN` mode and re-publishes inbound notifications
  locally. Implies `pg_publish!`. Use in Puma workers so they receive
  what other processes publish.

```ruby
# config/puma.rb (publish + receive, per worker after fork)
on_worker_boot     { Lux::Browser::Channel.pg_listen! }
on_worker_shutdown { Lux::Browser::Channel.pg_stop! }

# in a job process (publish only)
Lux::Browser::Channel.pg_publish!
```

NOTIFY is database-scoped. Pass the same `db_name:` to every call so
publisher and listeners share a database:

```ruby
Lux::Browser::Channel.pg_listen!(db_name: :events)
Lux::Browser::Channel.pg_publish!(db_name: :events)
```

Caveats:

* PG NOTIFY payload is capped at ~7.9 KB. Larger payloads raise
  `ArgumentError` on publish - ship a pointer + fetch detail.
* Each listening worker holds one extra PG connection in LISTEN mode
  (outside the Sequel pool). Count it against `max_connections`.
* No replay - the bridge is fire-and-forget.
* If the listener connection drops, it reconnects with bounded
  exponential backoff (1s -> 30s).
* Inbound NOTIFYs are dispatched through `Channel.local_publish`, so
  test code that subscribes a `Queue` directly continues to work.

Diagnostics:

```ruby
Lux::Browser::Channel.pg_publishing?  # bool - publish path routed through NOTIFY
Lux::Browser::Channel.pg_listening?   # bool - listener thread alive
Lux::Browser::Channel::PgBroker::PG_CHANNEL  # "lux_channel"
```

## API

| call | returns | notes |
|------|---------|-------|
| `Lux.browser.publish(name, data)` | nil | broadcast to all subscribers of `name` |
| `Lux::Browser::Channel.channels` | `[String]` | active channel names |
| `Lux::Browser::Channel.subscriber_count(name)` | Integer | |
| `Lux::Browser::Channel.reset!` | nil | drop every subscriber (tests only) |
| `Lux::Browser::Channel.pg_publish!(db_name: :main)` | true | route publishes through NOTIFY (jobs/rake) |
| `Lux::Browser::Channel.pg_listen!(db_name: :main)` | true | also start LISTEN thread (Puma workers) |
| `Lux::Browser::Channel.pg_stop!` | true | stop listener and disable NOTIFY publishing |
| `Lux::Browser::Channel.pg_publishing?` | Boolean | publish path routed through NOTIFY |
| `Lux::Browser::Channel.pg_listening?` | Boolean | listener thread alive |
| `Lux::Browser::Channel.local_publish(name, data)` | nil | in-process fan-out, bypass broker |
| `Lux::Browser::Channel.subscribe / .unsubscribe` | | **internal** - driven by `response.sse` |

## See also

* [`../../response/lib/sse.rb`](../../response/lib/sse.rb) - the SSE writer (`response.sse`)
* [`../README.md`](../README.md) - parent `Lux::Browser` (serves the `Lux.sse` client)
* [`../../../../plugins/job_runner/README.md`](../../../../plugins/job_runner/README.md) - PG LISTEN/NOTIFY pattern
