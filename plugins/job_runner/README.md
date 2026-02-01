# LuxJob - Job Runner Plugin

Database-backed job queue with cron-like scheduling for Lux framework.

## Setup

Require the plugin in your app:

```ruby
require 'job_runner/job_runner'
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

## Schema

| Field | Type | Description |
|-------|------|-------------|
| name | String | Job identifier |
| opts | Hash | Job arguments |
| run_at | Time | Next scheduled run |
| status_sid | String | s=Scheduled, r=Running, f=Failed, d=Done |
| retry_count | Integer | Number of retries after failure |
| response | String | Last execution result/error |

## Error Handling

Failed jobs are automatically rescheduled with exponential backoff:
- 1st failure: retry in 1 minute
- 2nd failure: retry in 2 minutes
- etc.

Logs are written to `./log/lux_job.log`
