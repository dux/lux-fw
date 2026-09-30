# LuxJob - Job Runner Plugin

Database-backed job queue with cron-like scheduling for Lux framework.
Uses Postgres `LISTEN/NOTIFY` for wake-ups and a `pg_try_advisory_lock`
for single-instance guarding - no polling, no row-based heartbeat.

## Setup

Load the plugin in your app:

```yaml
# config/config.yaml
plugins:
  - job_runner      # pulls in db (declared in the plugin's config.yaml)
```

The queue and runner need nothing else. The dashboard is a standalone web app
(`LuxJob::Server`, see **Web Dashboard**) that is started on demand and is not
part of the host app's routes.

## Usage

### Define Jobs

```ruby
LuxJob.class_eval do
  # Recurring job - runs every hour
  define :cleanup, every: 1.hour do
    # cleanup code
    'done'
  end

  # One-off job - triggered manually
  define :send_email do |opts|
    Mailer.send(opts[:to], opts[:subject], opts[:body])
    "sent to #{opts[:to]}"
  end

  # Job with custom timeout (default is 60s)
  define :long_report, every: 1.day, timeout: 300 do
    Report.generate_all
  end
end

# Initialize recurring jobs (creates DB records)
LuxJob.init
```

### Enqueue Jobs

```ruby
# Add a one-off job to the queue (NOTIFY wakes the runner immediately)
LuxJob.add :send_email, { to: 'user@example.com', subject: 'Hello' }
```

### Start the Runner

```bash
lux job_runner:start
```

Or programmatically:

```ruby
LuxJob.run  # blocks; uses LISTEN + advisory lock on one pinned connection
```

### Web Dashboard

`lux job_runner:web` starts one process that serves the dashboard and runs the
worker loop, bound to `$PORT` (or `-p PORT`). The port is required - without it
the task refuses to start rather than opening a listener. It is a small Sinatra
app, loaded only by that task - add `sinatra` and `puma` to the app Gemfile to
use it.

After boot the server prints `http://jobs.lvh.me:<port>` (`jobs.lvh.me` resolves
to `127.0.0.1`), so opening it keeps the request on a subdomain of the app's own
domain and the AuthCog callback is accepted. The server keeps no host
allow-list, which Sinatra's development default would turn into a `Host not
permitted` error. Set `LUX_JOB_URL` to override the printed URL, and
`LUX_JOB_BIND` (default `127.0.0.1`) to change the bind address.

The dashboard is Fez + pjax ready: navigation swaps the `#page` pjax region
instead of reloading the document. Fez is loaded from the app's own build
(`node_modules/fez` or `.libs/fez`, served at `/fez.js`) when present, and falls
back to `https://dux.github.io/fez/dist/fez.min.js`; `LUX_JOB_FEZ` overrides the
script URL.

Routes, all gated by AuthCog sign-in:

| Route                       | Purpose                                   |
|-----------------------------|-------------------------------------------|
| `/`                         | registered jobs + recent log              |
| `/jobs/<name>`              | per-job detail, trigger form and log tail |
| `POST /jobs/<name>/trigger` | enqueue a defined job with JSON opts      |
| `/api/poll`, `/api/log`     | last log id / log lines for the live tail |
| `/authcog`, `/logout`       | sign-in handoff and sign-out              |

Sign-in goes to authcog.com and the returned email must be in
`Lux.config.admin_emails`; anything else is refused at the callback with `403`
and no session. An empty `admin_emails` list fails closed. Required config:

```yaml
# config/config.yaml
secret: <session cookie secret>   # required
admin_emails:                     # who may open the dashboard
  - you@example.com
host: http://lvh.me:3000          # bounds which hosts a callback may use
# authcog_realm: auth             # optional authcog.com subdomain
```

The process runs the worker too, so don't run `lux job_runner:start` beside it -
`LuxJob.run` dies loudly when another runner already holds the advisory lock.

## Schema

| Field | Type | Description |
|-------|------|-------------|
| name | String | Job identifier |
| opts | Hash | Job arguments |
| run_at | Time | Next scheduled run |
| status_sid | String | s=Scheduled, r=Running, f=Failed, d=Done, x=Permanently failed |
| retry_count | Integer | Number of retries after failure |
| response | String | Last execution result/error |

## Constants

| Constant | Default | Description |
|----------|---------|-------------|
| MAX_RETRIES | 7 | Max retry attempts before permanent failure |
| RETRY_BASE_WAIT | 60 | Base retry delay in seconds, grows by 60% each attempt |
| DEFAULT_TIMEOUT | 60 | Default per-job timeout in seconds |
| NOTIFY_CHANNEL | 'lux_jobs' | PG NOTIFY channel the runner listens on |
| MIN_WAKE_SECS / MAX_WAKE_SECS | 1 / 300 | Bounds for the dynamic LISTEN timeout |

## Error Handling

Failed jobs are automatically rescheduled with 60% exponential backoff:
- 1st retry: 60s
- 2nd retry: 96s
- 3rd retry: ~154s
- ...up to 7 retries (~43 min total), then marked as permanently failed.

Jobs that exceed their timeout are treated as failures and follow the same retry logic.

Logs are written to `./log/lux_job.log`

`LuxJob.error 'message'` inside a job raises `LuxJobError`: an expected
failure. The job is marked failed with that message, nothing goes to the
exception log, and there is no backoff retry - it runs again at its next
scheduled time (`every:`, or an hour later for a one-off).

## Layout

```
plugins/job_runner/
  config.yaml                # plugins: [db]
  load/
    lux_job.rb               # model + runner (LISTEN/NOTIFY)
    lux_job_lock.rb          # pg_try_advisory_lock guard
  lib/
    lux_job_server.rb        # LuxJob::Server, standalone Sinatra dashboard + worker
  web/                       # ERB views for the dashboard
  Hammerfile                 # `lux job_runner:start` and `job_runner:web`
  spec/
    lux_job_spec.rb
    lux_job_server_spec.rb
    support/db.rb            # shared spec DB/plugin bootstrap
```
