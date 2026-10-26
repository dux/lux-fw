# Lux::Defer

Background thread pool for fire-and-forget work (logging, mail, audit trails).

## API

```ruby
Lux.defer { send_mail }                         # block gets the request snapshot (or no arg)
Lux.defer { |snap| audit snap[:user], snap[:url] } # snap is the frozen snapshot
Lux.defer(context: order, timeout: 120) { |o| o.sync! }
Lux.ctx.defer { ... }                               # same, from a request (Lux::Context#defer)

Lux::Defer.stats  # => { workers:, queued:, pool_size: }
```

* `context:` is what the block receives. It defaults to a frozen snapshot of the submitting request: `request_id`, `request_method`, `url`, `ip`, `user`.
* Inside the job `Lux.ctx` is a fresh context that keeps the request id, method and URL, and sets `User.current` from the snapshot user when the app defines `User.current=`.
* Session, params and response are not carried over.

## Pool

* Workers spawn lazily, up to `Lux.config.defer_pool_size` (default 3).
* A worker exits after 60 seconds without work; the next submit respawns one.
* When the queue already holds `pool_size` jobs, the job runs inline on the caller, so backpressure is automatic and no work is dropped.

## Timeout and errors

* `timeout:` defaults to `Lux.config.delay_timeout`: 3600 seconds in development and test, 30 in production.
* Errors and timeouts are written to `./log/defer_worker.log` (`Lux.logger(:defer_worker)`) and reported through `Lux.error.log`.
