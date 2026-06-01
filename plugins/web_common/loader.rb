# web_common - the shared web layer, bundled as a single plugin.
#
# Folds together what used to be six separate plugins so apps list one
# entry instead of six:
#
#   load/assets   - CdnAsset + ApplicationHelper template helpers
#   load/favicon  - `favicon` routing DSL (serve /favicon.ico + <head> links)
#   load/html     - form / input / table / menu / paginate / filter builders
#   lib/authcog   - central-auth callback landing controller
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

# Persist framework-internal `Lux.error.log` calls into the LuxException table.
module Lux::ErrorProxy
  def self.log_custom(err)
    LuxException.add err
  end
end
