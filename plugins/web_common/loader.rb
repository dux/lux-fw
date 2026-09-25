# web_common - the shared web layer, bundled as a single plugin.
#
#   load/assets   - CdnAsset + ApplicationHelper template helpers
#   load/favicon  - `favicon` routing DSL (serve /favicon.ico + <head> links)
#   load/html     - form / input / table / menu / paginate / filter builders
#   load/lib      - ApplicationApi, ModelApi, PG-backed exception logger
#   mount/        - /admin + /dev controllers and views
#
# Sign-in is the authcog plugin; apps list it next to this one.
#
# load/**/*.rb is auto-required after this file; only the pieces that must
# exist before that sweep are wired here.

# Persist framework-internal `Lux.error.log` calls into the LuxException table.
module Lux::ErrorProxy
  def self.log_custom(err)
    LuxException.add err
  end
end
