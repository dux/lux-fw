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

The JSON API (`LuxJobsApi`) and the admin dashboard views ship under
`mount/app/`, which the `Lux::Root` overlay treats as part of the app: the
API is eager-loaded with `./app` and mounted at `/api/lux_jobs`, the views
render at `/admin/plugins/lux_jobs`. Both need `web_common` (`ModelApi`,
the admin layout).

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

### Admin Dashboard

The dashboard lives at:

* `/admin/plugins/lux_jobs` - list of registered jobs and recent log
* `/admin/plugins/lux_jobs/show?name=<job>` - per-job page with trigger
  form and log tail

Admin auth is enforced by `LuxJobsApi` via `user.can.admin!`.

### API

`LuxJobsApi` is mounted at `/api/lux_jobs`. Actions:

| Action            | Type       | Purpose                                  |
|-------------------|------------|------------------------------------------|
| `trigger`         | collection | Enqueue a defined job by name + opts     |
| `poll`            | collection | Return last log timestamp for polling    |
| `log`             | collection | Tail recent log lines (filterable)       |
| `restart`         | member     | Reset a job row to run now and wake the runner |

Nothing runs a job in a web process: only the runner holds the advisory lock
that keeps a job from running twice.

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
    lux_job_exporter.rb
  mount/app/
    api/lux_jobs_api.rb      # LuxJobsApi, /api/lux_jobs
    views/admin/plugins/lux_jobs/   # dashboard
  Hammerfile                 # `lux job_runner:start`
  spec/lux_job_spec.rb
```
