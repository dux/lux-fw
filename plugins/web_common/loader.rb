# web_common - the shared web layer, bundled as a single plugin.
#
#   load/assets   - CdnAsset + HtmlHelper template helpers (response)
#   load/html     - form / input / table / menu / paginate builders
#   load/lib      - ApplicationApi, ModelApi, router helpers (/lux server_info),
#                   exception writer
#   assets/js     - browser sources, apps import them as @web-common/js/...
#   mount/        - /dev router and views
#
# Sign-in is the authcog plugin; apps list it next to this one.
#
# load/**/*.rb is auto-required after this file; only the pieces that must
# exist before that sweep are wired here.

# Persist framework-internal `Lux.error.log` calls as JSON lines in
# log/app.exceptions.log (read by dboss). Expected HTTP errors are skipped.
Lux.error.on_log do |err|
  next if Lux::Api::Response.client_error?(err)   # Lux::Error <500, Api::Error, policy, validation
  ExceptionWriter.new(err).write
end
