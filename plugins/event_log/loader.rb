# LuxEventLog - event log entries in an UNLOGGED PG table
#
# Requires the db plugin, load it first:
#   Lux.plugin :db
#   Lux.plugin :event_log
#
# Usage:
#   LuxEventLog.log ['page_view', 'mobile'], '/pricing', { referrer: 'google.com' }
#
# Admin dashboard ships as a haml template under mount/. After
# `Lux.plugin :event_log`, run `lux mount event_log` once to symlink it
# into the host app. The dashboard then lives at /admin/plugins/event_log.

require_relative 'lib/lux_event_log'
require_relative 'lib/lux_event_log_view'
