# Mounts LuxJobWeb at /admin/plugins/job_runner.
# Auto-evaluated by `plugin_routes` in the host app's main routes.
# `lux_job_web` is not required by loader.rb to keep sinatra out of the
# default boot; pull it in here, only when the host wires up the dashboard.

require_relative 'lib/lux_job_web'

mount LuxJobWeb => '/admin/plugins/job_runner'
