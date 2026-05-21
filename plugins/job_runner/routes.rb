# Routes LuxJobWeb (Rack/Sinatra app) at /admin/plugins/job_runner.
# Auto-evaluated by `plugin_routes` in the host app's main routes.
# `lux_job_web` is not required by loader.rb to keep sinatra out of the
# default boot; pull it in here, only when the host wires up the dashboard.
#
# `map '/abs/path' => RackClass` dispatches every matching request to
# `RackClass.call(env)` and renders the Rack response - no SCRIPT_NAME
# rewriting, the app sees the full path.

require_relative 'lib/lux_job_web'

map '/admin/plugins/job_runner' => LuxJobWeb
