# Reserved /pdf/ root - printable pages (mirrors /admin/). Models are loaded
# here with `nav.load_models` (router scope) so PdfRouter templates receive
# @<model> via the normal dispatch ivar copy. Access is gated inside
# PdfRouter (logged-in preview, or a signed URL for the headless renderer).
#
# Wire in the host app routes with:  plugin_route :pdf
map 'pdf' do
  # The .pdf request only forwards to the headless renderer (no template), so
  # skip loading there; the HTML page it then fetches loads the model.
  # PdfRouter reads nav.source_path for the signed URL, so it does not
  # matter that load_models rewrites the ref segment out of nav.path.
  nav.load_models unless nav.format == :pdf

  map 'pdf#call'
end
