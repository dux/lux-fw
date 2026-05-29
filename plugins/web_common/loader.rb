# web_common - the shared web layer, bundled as a single plugin.
#
# Folds together what used to be six separate plugins so apps list one
# entry instead of six:
#
#   load/assets   - CdnAsset + ApplicationHelper template helpers
#   load/favicon  - Lux::Favicon <link> builder (+ routes.rb for legacy polling)
#   load/header   - lux.header per-request <head> builder
#   load/html     - form / input / table / menu / paginate / filter builders
#   lib/authcog   - central-auth login + landing controller
#   lib/lux_*     - PG-backed exception logger (+ mount/ for the /admin viewer)
#
# load/**/*.rb is auto-required after this file; only the pieces that must
# exist before that sweep, or that are not under load/, are wired here.

require 'digest'

# -- authcog --------------------------------------------------------------
# Single controller, routed by the app as `map 'authcog', 'authcog#call'`.
require_relative 'lib/authcog_controller'

# -- admin_web / exception logger ----------------------------------------
require_relative 'lib/lux_exception'
require_relative 'lib/lux_exception_log'

# Route framework-internal `Lux.error.log` calls into the LuxException table.
module Lux::ErrorProxy
  LOG_DEDUPE_KEY ||= 'lux:error_log:last_fingerprint'.freeze
  LOG_DEDUPE_TTL ||= 60

  def self.log(err)
    # Dedupe burst-repeats: if the last logged error has the same class and
    # was raised from the same app-level callsite, drop it. Uses Lux.cache
    # server directly so it works outside an HTTP request context too.
    root = Lux.root.to_s
    site = (err.backtrace || []).find { |l| l.start_with?(root) }
    fingerprint = "#{err.class}@#{site}"

    cache = Lux.cache.server rescue nil
    if cache
      return if (cache.get(LOG_DEDUPE_KEY) rescue nil) == fingerprint
      cache.set(LOG_DEDUPE_KEY, fingerprint, LOG_DEDUPE_TTL) rescue nil
    end

    LuxException.add err
  rescue Sequel::DatabaseError
    # lux_exceptions table not migrated yet (run `lux db:am`). Skip DB logging
    # rather than mask the original error with a secondary failure.
  end
end
