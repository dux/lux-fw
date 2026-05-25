# LuxJob - Job Runner Plugin

Database-backed job queue with cron-like scheduling for Lux framework.
Uses Postgres `LISTEN/NOTIFY` for wake-ups and a `pg_try_advisory_lock`
for single-instance guarding - no polling, no row-based heartbeat.

## Setup

Load the plugin in your app:

```ruby
Lux.plugin 'job_runner'
```

Symlink the JSON API into the host:

```sh
lux mount job_runner
```

That places under your app root:

```
app/api/lux_jobs_api.rb
```

The admin dashboard views (`/admin/plugins/lux_jobs`) ship with the
`admin_web` plugin instead - mount that to get them:

```sh
lux mount admin_web
```

Edit either set in place - they're your files now; the plugin only provides
the starting point. `lux mount` is idempotent.

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

After `lux mount job_runner`, the dashboard lives at:

* `/admin/plugins/lux_jobs` - list of registered jobs and recent log
* `/admin/plugins/lux_jobs/show?name=<job>` - per-job page with trigger
  form and log tail

Admin auth is enforced by `LuxJobsApi` via `user.can.admin!`.

### API

`LuxJobsApi` is mounted by the host's `Lux::Api` auto-mount, typically
at `/api/lux_jobs`. Actions:

| Action            | Type       | Purpose                                  |
|-------------------|------------|------------------------------------------|
| `trigger`         | collection | Enqueue a defined job by name + opts     |
| `poll`            | collection | Return last log timestamp for polling    |
| `log`             | collection | Tail recent log lines (filterable)       |
| `restart`         | member     | Reset a job row to run now               |
| `run`             | member     | Run the job synchronously in a thread    |

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

## Layout

```
plugins/job_runner/
  loader.rb                  # requires LuxJob + LuxJobLock
  lib/
    lux_job.rb               # model + runner (LISTEN/NOTIFY)
    lux_job_lock.rb          # pg_try_advisory_lock guard
    lux_job_policy.rb
    lux_job_exporter.rb
  mount/                     # symlinked into the host via `lux mount`
    app/
      api/lux_jobs_api.rb
  Hammerfile                 # `lux job_runner:start`, `:restart`
```
