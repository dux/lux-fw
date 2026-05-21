# Routes LuxExceptionWeb (Rack/Sinatra app) at /admin/plugins/exception_logger.
# Auto-evaluated by `plugin_routes` in the host app's main routes.
#
# `map '/abs/path' => RackClass` dispatches every matching request to
# `RackClass.call(env)` and renders the Rack response - no SCRIPT_NAME
# rewriting, the app sees the full path.

map '/admin/plugins/exception_logger' => LuxExceptionWeb
