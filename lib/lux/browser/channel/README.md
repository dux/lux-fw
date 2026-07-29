# Lux::Browser::Channel

Pub/sub channels by name. Backbone for the SSE stream served at the baked-in
`/_lux_/stream` endpoint. Publish from anywhere on the server with
`Lux.channel(target).push(data)` (or, in a request,
`lux.browser.publish(name, data)`); subscribe from the client with
`Lux.subscribe`.

A browser holds **one** stream, scoped to its session. The client cannot ask
for a channel - the server decides what the connection carries - so targeting
a single user is both the simplest thing to do and the secure one.

Delivery across processes is a broker's job, chosen by one config key. The
core knows nothing about any backend.

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

Lux.channel(user).push(type: :inbox, count: 3)               # one person
Lux.channel("org:#{org.ref}").push(message: 'Deploy done')   # everyone in the org

# Strings, hashes, arrays, numbers - anything JSON-serialisable.
```

**The channel name is the audience.** A connection is subscribed to exactly
what `session_channels` returned for its session, so `user:<ref>` reaches one
person and nobody else. Anything pushed to a shared name (`org:<ref>`) is
visible to everyone whose session resolves to it.

Because the name is the audience, it always carries a prefix. Pass any model
with a `ref` and it becomes `"<model>:<ref>"`; pass a string and it must name
its audience itself:

```ruby
Lux.channel(user)          # => "user:<ref>"
Lux.channel('user:abc')    # taken as-is
Lux.channel('abc')         # ArgumentError - a bare ref is nobody's channel
```

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
Lux.channel(user).push(topic: 'zip-import:abc', html: 'Uploading...')
```

```js
Lux.subscribe('zip-import:abc', msg => log.append(msg.html))
```

Topics are routing, not security - anyone receiving the channel receives
every topic on it.

```ruby
# --- diagnostics ---

Lux::Browser::Channel.channels                      # ["user:42", "org:7"]
Lux::Browser::Channel.subscriber_count('user:42')   # int
Lux::Browser::Channel.broker                        # the live broker
Lux::Browser::Channel.reset!                        # drop subscribers + broker (tests)
```

## Picking a backend

One key, and the scheme picks the broker:

```yaml
# config.yaml - only needed to override the default
channel_url: postgres:main     # ENV['CHANNEL_URL'] wins if set
```

| `channel_url` | broker | delivery |
|---|---|---|
| `memory:` / empty | `MemoryBroker` | this process only |
| `postgres:` / `postgres:<db>` | `PgBroker` | every process on that Lux DB, via LISTEN/NOTIFY |

**The default is `postgres:main`** whenever a main DB is configured, and memory
otherwise (or in test, which is single-process). Most apps therefore need no
config at all: the usual shape is a web process plus a job process, and an
in-process default fails silently there - the job publishes and no browser
hears it. Set `channel_url:` empty to force in-process.

Nothing else is needed: no initializer call, no per-process setup. `Lux::Boot`
starts a listener only where one is wanted (`Lux.runtime.web?`), and the puma
worker hook re-arms it after fork.

### Writing a broker

Subclass `Lux::Browser::Channel::Broker` (see `brokers/base.rb`) and implement
`publish`; the rest is optional and no-ops by default.

```ruby
class MyBroker < Lux::Browser::Channel::Broker
  def publish name, data
    # get it to every process holding subscribers, however you like
  end

  def listen!     ; end   # start receiving -> Channel.local_publish(name, data)
  def stop!       ; end
  def after_fork! ; end
end
```

Register the scheme in `Broker::SCHEMES` and drop the file in `brokers/`, or
assign an instance directly with `Lux::Browser::Channel.broker = MyBroker.new`.
A broker that hands messages to an external process (Bun, Node, a queue) needs
nothing from the core beyond this.

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
* `Lux.channel(target).push(data)` hands `data` to the broker, which gets it to
  every process holding subscribers; each of those calls `local_publish`, which
  fans out to the queues.
* `/_lux_/stream` opens a `text/event-stream` response, attaches one queue
  to every channel the session resolves to, yields SSE frames until the
  client disconnects, and detaches in `ensure`.
* Every frame is `{channel, data}` JSON on the default message event. There are
  no per-channel event names, which is what lets a page hold one connection
  regardless of what it subscribes to.
* The client (`Lux.subscribe`) opens one `EventSource` per page and routes on
  the `channel` field, plus the payload's `topic` when present.

## Heartbeats and disconnects

The server emits `: ping\n\n` every 30 seconds so proxies don't reap idle
connections. Client disconnects raise `IOError` / `EPIPE` / `ECONNRESET`
inside the SSE writer; the subscription is closed in an `ensure` block.

## Limitations

* **Nothing is replayed.** A connection receives what is published while it is
  open, and that is all - there is no history and no `Last-Event-ID` catch-up.
  A tab that drops mid-run has missed whatever went out in the gap. Push state
  the client can re-fetch (a "reload this" pointer) rather than deltas it must
  have seen, and never rely on the stream alone to end a workflow.
* **Thread per connection.** Every open stream parks a server thread for as
  long as the tab is open, so the thread cap is also the concurrent-viewer
  ceiling per worker.
* **Delivery is at-most-once.** Both brokers are fire-and-forget; a process
  that starts after a publish never sees it.

## Cross-process: PG LISTEN/NOTIFY

`channel_url: postgres:main` and nothing else. Publishing borrows a pooled
Sequel connection and returns; a process that holds browser connections also
runs a background thread with one dedicated PG connection in `LISTEN` mode,
re-publishing inbound notifications locally.

**A listener does not survive `fork`.** A clustered puma loads the app in the
master, so the thread starts there; every worker then inherits the LISTEN socket
and nothing that reads it. `lux_boot`'s worker-boot hook calls
`Channel.broker.after_fork!`, which notices the state came from another process
and starts a fresh thread and connection. Any other forking server has to make
the same call after its fork. `broker.listening?` answers for the current
process only.

NOTIFY is database-scoped: `postgres:events` publishes and listens on the Lux DB
named `events`, and only processes pointed at the same one will agree.

Caveats:

* PG NOTIFY payload is capped at ~7.9 KB. Larger payloads raise
  `ArgumentError` on publish - ship a pointer + fetch detail. The limit belongs
  to this broker, so an app never has to know which backend it is on.
* Each listening worker holds one extra PG connection in LISTEN mode
  (outside the Sequel pool). Count it against `max_connections`.
* If the listener connection drops, it reconnects with bounded
  exponential backoff (1s -> 30s).
* Inbound NOTIFYs are dispatched through `Channel.local_publish`, so
  test code that subscribes a `Queue` directly continues to work.

## API

| call | returns | notes |
|------|---------|-------|
| `Lux.channel(target).push(data)` | nil | broadcast to all subscribers of that channel |
| `lux.browser.publish(name, data)` | nil | same, in a request context |
| `Lux::Browser::Channel.channel_name(target)` | String | model -> `"<model>:<ref>"`; string must be prefixed |
| `Lux::Browser::Channel.session_channels { \|lux\| [...] }` | | set the resolver (initializer) |
| `Lux::Browser::Channel.channels_for(lux)` | `[String]` | what that session receives; `[]` on raise |
| `Lux::Browser::Channel.broker` | Broker | built from `channel_url` on first use |
| `Lux::Browser::Channel.broker = obj` | | override (tests, or a custom backend) |
| `Lux::Browser::Channel.channels` | `[String]` | active channel names |
| `Lux::Browser::Channel.subscriber_count(name)` | Integer | |
| `Lux::Browser::Channel.reset!` | nil | drop every subscriber and the broker (tests only) |
| `Lux::Browser::Channel.local_publish(name, data)` | nil | in-process fan-out; what a broker calls inbound |
| `Lux::Browser::Channel.subscribe / .unsubscribe` | | **internal** - driven by `response.sse` |

## See also

* [`../../../../doc/browser-push.md`](../../../../doc/browser-push.md) - task-oriented walkthrough; start here
* [`./brokers/base.rb`](./brokers/base.rb) - the broker contract
* [`../../response/lib/sse.rb`](../../response/lib/sse.rb) - the SSE writer (`response.sse`)
* [`../README.md`](../README.md) - parent `Lux::Browser` (serves the `Lux.sse` client)
* [`../../../../plugins/job_runner/README.md`](../../../../plugins/job_runner/README.md) - PG LISTEN/NOTIFY pattern
