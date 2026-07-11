# Reserved /pdf/ root - printable pages (mirrors /admin/). Models are loaded
# here (router scope, like load_objects) so PdfController templates receive
# @<model> via the normal dispatch ivar copy. Access is gated inside
# PdfController (logged-in preview, or a signed URL for the headless renderer).
#
# Wire in the host app routes with:  plugin_route :pdf
if nav.root == 'pdf'
  # Canonical path before load_models rewrites the ref segment - used by
  # PdfController to build/verify the signed URL.
  @pdf_path = '/' + nav.path.join('/')

  # The .pdf request only forwards to the headless renderer (no template), so
  # skip loading there; the HTML page it then fetches loads the model.
  nav.load_models unless nav.format == :pdf

  call 'pdf#call'
end
