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

ENV['PORT_JOB'] ||= '3001'

require_relative 'lib/lux_job'
require_relative 'lib/lux_job_lock'
