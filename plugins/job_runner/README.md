# LuxJob - Job Runner Plugin

Database-backed job queue with cron-like scheduling for Lux framework.

## Setup

Load the plugin in your app:

```ruby
Lux.plugin 'job_runner'
```

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
# Add a one-off job to the queue
LuxJob.add :send_email, { to: 'user@example.com', subject: 'Hello' }
```

### Start the Runner

```bash
rake job_runner:start
```

Or programmatically:

```ruby
LuxJob.run  # blocks and polls every 3 seconds
```

### Web Dashboard

```bash
rake job_runner:web[password]
```

Or mount in your Lux app:

```ruby
require 'job_runner/lib/lux_job_web'
LuxJobWeb.password = 'secret'
mount LuxJobWeb, at: '/sys-runner'
```

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

## Error Handling

Failed jobs are automatically rescheduled with 60% exponential backoff:
- 1st retry: 60s
- 2nd retry: 96s
- 3rd retry: ~154s
- ...up to 7 retries (~43 min total), then marked as permanently failed.

Jobs that exceed their timeout are treated as failures and follow the same retry logic.

Logs are written to `./log/lux_job.log`
