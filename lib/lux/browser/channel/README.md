# Lux::Browser::Channel

In-process pub/sub channels by name. Backbone for the SSE stream served at
the baked-in `/_lux_/stream` endpoint. Publish from anywhere on the server
with `Lux.channel(name).push(data)` (or, in a request,
`lux.browser.publish(name, data)`); subscribe from the client with
`Lux.subscribe`.

A browser holds **one** stream, scoped to its session. The client cannot ask
for a channel - the server decides what the connection carries - so targeting
a single user is both the simplest thing to do and the secure one.

Nested under `Lux::Browser` because the only consumer today is the
SSE writer (`response/lib/sse.rb`) which fans messages out to the
`Lux.subscribe` client module served at `/_lux_/client.js`.

## Full example

```ruby
# --- who gets a stream, and what it carries (once, in an initializer) ---

Lux::Browser::Channel.session_channels do |lux|
  ref = lux.session[:user_ref] or next []      # [] -> no stream for guests
  ["user:#{ref}", "org:#{lux.session[:org_ref]}"]
end

# --- publish from anywhere (jobs, callbacks, actions, defer'd threads) ---

Lux.channel("user:#{user.ref}").push(type: :inbox, count: 3)   # one person
Lux.channel("org:#{org.ref}").push(message: 'Deploy done')     # everyone in the org

# Strings, hashes, arrays, numbers - anything JSON-serialisable.
```

**The channel name is the audience.** A connection is subscribed to exactly
what `session_channels` returned for its session, so `user:<ref>` reaches one
person and nobody else. Anything pushed to a shared name (`org:<ref>`) is
visible to everyone whose session resolves to it.

```html
<!-- client: just include /_lux_/client.js and call subscribe -->
<script src="/_lux_/client.js"></script>
<script>
  Lux.subscribe('user:42', msg => inbox.update(msg))

  // Opens one EventSource on first subscribe and keeps it. Subscribing and
  // unsubscribing is local bookkeeping - it never reopens the connection,
  // because the server takes no channel parameters.

  Lux.unsubscribe('user:42', fn)   // drop one handler
  Lux.unsubscribe('user:42')       // drop the name entirely
  Lux.disconnect()                 // close the stream
  Lux.onConnectionChange(state => ...)   // 'open' | 'closed'
</script>
```

One session channel can carry many logical streams. Give the payload a
`topic` and subscribe to that name directly - the client matches a handler
against both the frame's channel and its `topic`:

```ruby
Lux.channel("user:#{user.ref}").push(topic: 'zip-import:abc', html: 'Uploading...')
```

```js
Lux.subscribe('zip-import:abc', msg => log.append(msg.html))
```

Topics are routing, not security - anyone receiving the channel receives
every topic on it.

```ruby
# --- diagnostics ---

Lux::Browser::Channel.channels                          # ["notifications", "user:42"]
Lux::Browser::Channel.subscriber_count(:notifications)  # int
Lux::Browser::Channel.reset!                            # drop every subscriber (tests only)
```

## Endpoint

The framework intercepts `/_lux_/stream` and streams one session-scoped SSE
feed. **It takes no parameters.** What a connection carries comes from
`Lux::Browser::Channel.session_channels`, evaluated against the (encrypted)
session cookie - so there is nothing for a client to tamper with and no
per-channel authorization to write.

* no resolver configured -> `501`
* resolver returns `[]` (guest) -> `403`

Note the resolver runs before route resolution, so anything a controller
`before` filter would normally set up is not available yet - read the session
directly rather than reaching for a current-user helper.

`response.sse(*channels)` still exists for app-defined SSE endpoints,
but for the standard publish/subscribe surface you no longer need a
custom controller.

`Lux::Browser::Channel.subscribe(name, queue)` /
`Lux::Browser::Channel.unsubscribe(name, queue)` are internal - used by
the SSE writer to attach and detach a queue per client.

## How it works

* `Lux::Browser::Channel` keeps a `name -> [Queue, ...]` registry guarded by a Mutex.
* `Lux.channel(name).push(data)` fans `data` out to every queue currently
  subscribed to `name` (or, with the broker on, via PG NOTIFY).
* `/_lux_/stream` opens a `text/event-stream` response, attaches one queue
  to every channel the session resolves to, yields SSE frames until the
  client disconnects, and detaches in `ensure`.
* Every frame is `{channel, data}` JSON on the default message event, with a
  monotonic `id:`. There are no per-channel event names, which is what lets a
  page hold one connection regardless of what it subscribes to.
* The client (`Lux.subscribe`) opens one `EventSource` per page and routes on
  the `channel` field, plus the payload's `topic` when present.

## Heartbeats and disconnects

The server emits `: ping\n\n` every 30 seconds so proxies don't reap idle
connections. Client disconnects raise `IOError` / `EPIPE` / `ECONNRESET`
inside the SSE writer; the subscription is closed in an `ensure` block.

## Limitations

* **In-process by default.** A publish in worker A does not reach subscribers
  in worker B unless the PG broker is started (see below).
* **Replay is short.** Each process retains the last `HISTORY_SIZE` (100)
  messages per channel and replays what a reconnecting `EventSource` missed,
  via `Last-Event-ID`. That covers a dropped connection, not a page reload and
  not a process that started after the message was published - if the state
  must survive either, persist it and render it alongside the live stream.
* **Ids assume one publisher per channel.** They are assigned by the
  publishing process; two processes publishing to the same name hand out the
  same ids. Give each publisher its own channel name if that matters.

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
* No replay in the bridge itself - it is fire-and-forget. Retention lives in
  `Channel`, per process, and only covers what that process received.
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
| `Lux.channel(name).push(data)` | nil | broadcast to all subscribers of `name` |
| `lux.browser.publish(name, data)` | nil | same, in a request context |
| `Lux::Browser::Channel.session_channels { \|lux\| [...] }` | | set the resolver (initializer) |
| `Lux::Browser::Channel.channels_for(lux)` | `[String]` | what that session receives; `[]` on raise |
| `Lux::Browser::Channel.history_since(name, id)` | `[Hash]` | retained messages newer than `id` |
| `Lux::Browser::Channel.channels` | `[String]` | active channel names |
| `Lux::Browser::Channel.subscriber_count(name)` | Integer | |
| `Lux::Browser::Channel.reset!` | nil | drop every subscriber (tests only) |
| `Lux::Browser::Channel.pg_publish!(db_name: :main)` | true | route publishes through NOTIFY (jobs/rake) |
| `Lux::Browser::Channel.pg_listen!(db_name: :main)` | true | also start LISTEN thread (Puma workers) |
| `Lux::Browser::Channel.pg_stop!` | true | stop listener and disable NOTIFY publishing |
| `Lux::Browser::Channel.pg_publishing?` | Boolean | publish path routed through NOTIFY |
| `Lux::Browser::Channel.pg_listening?` | Boolean | listener thread alive |
| `Lux::Browser::Channel.local_publish(name, data, id = nil)` | nil | in-process fan-out, bypass broker |
| `Lux::Browser::Channel.subscribe / .unsubscribe` | | **internal** - driven by `response.sse` |

## See also

* [`../../response/lib/sse.rb`](../../response/lib/sse.rb) - the SSE writer (`response.sse`)
* [`../README.md`](../README.md) - parent `Lux::Browser` (serves the `Lux.sse` client)
* [`../../../../plugins/job_runner/README.md`](../../../../plugins/job_runner/README.md) - PG LISTEN/NOTIFY pattern
