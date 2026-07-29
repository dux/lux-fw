# Pushing to a browser

How to send a message from the server to one user's open page, start to finish.

The shape is the same as socket.io or Pusher - name a channel, push to it,
subscribe to it by name. One connection per tab carries every channel.

```ruby
Lux.channel(user).push(html: 'Import finished')     # server
```
```js
Lux.subscribe('user:abc123', msg => console.log(msg.html))   // browser
```

Transport is SSE, not WebSocket. For server -> client push they behave the same,
and SSE is plain HTTP: proxies pass it through, `curl` can read it, and the
browser reconnects on its own.

## Setup

Two steps, once per app.

**1. Say who may hear what.** This is the entire access-control story, so it is
the only piece you have to write. Put it in `config/initializers/stream.rb`:

```ruby
Lux::Browser::Channel.session_channels do |lux|
  ref = lux.session[:user_ref] or next []      # [] -> guests get no stream
  ["user:#{ref}"]
end
```

The endpoint takes **no parameters**: a browser receives exactly what this block
returns for its own (encrypted) session cookie. A client cannot ask for someone
else's channel because there is nothing to ask with - which is why there is no
per-channel authorization to write.

It runs before route resolution, so `User.current` is not set up yet. Read the
session directly.

**2. Load the client.** In your layout:

```haml
%script{ src: '/_lux_/sse.js' }
```

That is it. No route to declare, no controller, no config. Cross-process
delivery is already on by default - see [Two processes](#two-processes).

## Sending

`Lux.channel(target)` takes a model or a string:

```ruby
Lux.channel(user).push(html: 'Done')            # "user:<ref>"
Lux.channel(org).push(html: 'New order')        # "org:<ref>"
Lux.channel("user:#{ref}").push(count: 3)       # explicit
```

A model becomes `"<model>:<ref>"`. A string is taken as-is but **must** carry a
prefix - `Lux.channel('abc123')` raises rather than quietly creating a channel
nobody is subscribed to. The channel name is the audience, so a bare ref is
always a mistake.

The payload is anything JSON-serialisable. Push from anywhere: a controller, a
model callback, a job, a `Lux.defer` thread.

## Receiving

```js
Lux.subscribe('user:abc123', msg => { ... })   // add a handler
Lux.unsubscribe('user:abc123', fn)             // drop one handler
Lux.unsubscribe('user:abc123')                 // drop the name
Lux.onConnectionChange(state => ...)           // 'open' | 'closed'
Lux.disconnect()                               // close the stream
```

The connection opens on the first `subscribe` and closes when the last handler
goes - you do not manage it. Subscribing and unsubscribing is local bookkeeping
and never reopens the socket, because the server takes no channel parameters.

`onConnectionChange` fires immediately with the current state, which is
`'closed'` until the socket is up. Only treat a close as a real drop once you
have seen an `'open'`.

### Many logs on one stream

A `topic` inside the payload routes within a channel, so one user stream can
drive several independent widgets:

```ruby
Lux.channel(user).push(topic: "import:#{job.ref}", html: 'Uploading...')
```
```js
Lux.subscribe(`import:${ref}`, msg => log.append(msg.html))
```

Topics are routing, not security - everyone receiving the channel receives every
topic on it.

## Two processes

The common shape is a `web` process plus a `job` process. They are separate OS
processes, so a push from the job cannot reach a browser connection living in
the web process - something has to carry it across.

That is what `channel_url` does, and it **defaults to `postgres:main`** whenever
a main DB is configured. Most apps never set it:

```yaml
channel_url: postgres:main   # the default; ENV['CHANNEL_URL'] wins
channel_url:                 # empty - in-process only
```

The cost is one PG connection per **web worker** (not per viewer - 100 open tabs
still cost one), held open in `LISTEN` mode. Publishing borrows a pooled
connection and returns, so a job process holds nothing extra.

In test it defaults to in-process, because a suite is one process and NOTIFY
would publish into the void.

## What it does not do

Read this bit - it decides how you design the feature.

* **Nothing is replayed.** A connection receives what is published while it is
  open, and that is all. There is no history and no catch-up on reconnect, so a
  tab that drops for ten seconds has permanently missed those messages.

  Push state the client can act on independently, not deltas it must have seen.
  If a run ends with "done, now refresh", also make that state fetchable, and
  handle `onConnectionChange` so a dropped tab can recover instead of waiting
  forever for a message that is never coming.

* **Delivery is at-most-once.** Both backends are fire-and-forget. A process
  that starts after a push never sees it.

* **One thread per open connection.** Your server's thread cap is also the
  concurrent-viewer ceiling per worker (puma's default 100). Well beyond typical
  use, but it is a real limit, so do not lower `threads`.

* **~7.9 KB per message** on the PG backend - a NOTIFY payload limit. Push a
  pointer, not a page.

## Another backend

`channel_url`'s scheme picks the backend. To add one - a Bun/Node process
holding the sockets, a hosted service, Redis - subclass `Broker`, implement
`publish`, and register the scheme:

```ruby
class MyBroker < Lux::Browser::Channel::Broker
  def publish name, data
    # get it to every process holding subscribers
  end

  def listen!     ; end   # start receiving -> Channel.local_publish(name, data)
  def stop!       ; end
  def after_fork! ; end
end
```

Nothing in the core changes. For a one-off, assign an instance directly:
`Lux::Browser::Channel.broker = MyBroker.new`.

## Debugging

```ruby
Lux::Browser::Channel.broker            # which backend is live
Lux::Browser::Channel.broker.listening? # is this process receiving
Lux::Browser::Channel.channels          # channel names with subscribers here
Lux::Browser::Channel.subscriber_count('user:abc')
```

```js
Lux.streamState()   // { connected, state, names }
```

The endpoint answers `501` when no `session_channels` resolver is registered and
`403` when it returns `[]` (a guest). You can read a stream straight from the
shell:

```sh
curl -N -H 'Cookie: <your session cookie>' http://localhost:3000/_lux_/stream
```

Expect `: connected`, then `: ping` every 30 seconds, then `data: {...}` frames.

## See also

* [`../lib/lux/browser/channel/README.md`](../lib/lux/browser/channel/README.md) - API reference
* [`../lib/lux/browser/channel/brokers/base.rb`](../lib/lux/browser/channel/brokers/base.rb) - the broker contract
* [`../lib/lux/response/lib/sse.rb`](../lib/lux/response/lib/sse.rb) - `response.sse` for an app-defined endpoint
