# web_common - the shared web layer, bundled as a single plugin.
#
# Folds together what used to be six separate plugins so apps list one
# entry instead of six:
#
#   load/assets   - CdnAsset + ApplicationHelper template helpers
#   load/favicon  - `favicon` routing DSL (serve /favicon.ico + <head> links)
#   load/html     - form / input / table / menu / paginate / filter builders
#   lib/lux_*     - PG-backed exception logger (+ mount/ for the /admin viewer)
#
# Sign-in lives in the authcog plugin, pulled in by config.yaml.
#
# load/**/*.rb is auto-required after this file; only the pieces that must
# exist before that sweep, or that are not under load/, are wired here.

# Persist framework-internal `Lux.error.log` calls into the LuxException table.
module Lux::ErrorProxy
  def self.log_custom(err)
    LuxException.add err
  end
end
