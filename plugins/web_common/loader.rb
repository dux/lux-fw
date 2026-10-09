# web_common - the shared web layer, bundled as a single plugin.
#
#   load/assets   - CdnAsset + ApplicationHelper template helpers
#   load/html     - form / input / table / menu / paginate / filter builders
#   load/lib      - ApplicationApi, ModelApi, exception writer, legacy exception logger
#   assets/js     - browser sources, apps import them as @web-common/js/...
#   mount/        - /dev controller and views
#
# Sign-in is the authcog plugin; apps list it next to this one.
#
# load/**/*.rb is auto-required after this file; only the pieces that must
# exist before that sweep are wired here.

# Persist framework-internal `Lux.error.log` calls as JSON lines in
# log/app.exceptions.log (read by dboss).
Lux.error.on_log { |err| ExceptionWriter.new(err).write }
