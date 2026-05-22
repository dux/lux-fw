# LuxJob - Database-backed job queue with cron-like scheduling
#
# Usage:
#   # Define jobs
#   LuxJob.class_eval do
#     define :my_job, every: 1.hour do
#       # job code
#     end
#
#     define :send_email do |opts|
#       # one-off job triggered via LuxJob.add
#     end
#   end
#
#   LuxJob.init  # creates DB records for recurring jobs
#
#   # Enqueue one-off job
#   LuxJob.add :send_email, { to: 'user@example.com' }
#
#   # Start the runner (blocks)
#   LuxJob.run
#
# Admin dashboard ships as haml templates + an API class under mount/.
# After `Lux.plugin :job_runner`, run `lux mount job_runner` once to
# symlink them into the host app. The dashboard then lives at
# /admin/plugins/lux_jobs (requires the admin_web plugin).

require_relative 'lib/lux_job'
require_relative 'lib/lux_job_lock'
