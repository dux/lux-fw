# LuxEventLog - event log entries in an UNLOGGED PG table
#
# Requires the db plugin, load it first:
#   Lux.plugin :db
#   Lux.plugin :event_log
#
# Usage:
#   LuxEventLog.log ['page_view', 'mobile'],
#     user_ref: user.ref, info: 'Viewed pricing', path: '/pricing'
#
# Admin dashboard ships as a haml template under mount/, which Lux::Root
# exposes to the host app. The dashboard is live at /admin/plugins/event_log
# as soon as the plugin loads.

require_relative 'lib/lux_event_log'
require_relative 'lib/lux_event_log_view'
