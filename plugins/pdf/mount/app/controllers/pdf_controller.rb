# Reserved /pdf/ root (mirrors /admin/). Renders print-optimised pages from
# app/views/pdf/ in the :pdf layout, which paginates them into A4 pages with
# Paged.js - the very same engine used to render the downloadable PDF, so the
# on-screen preview and the PDF are identical.
#
# Access is dual-gated: logged-in users get the preview and the PDF; the
# headless renderer fetches the HTML page unauthenticated, so it is let in by a
# short-lived HMAC-signed URL that render_pdf builds via .sign. A signature never
# opens the .pdf itself, so a leaked link cannot keep a server Chrome busy.
#
#   GET /pdf/demo                 -> preview (Paged.js paginates on screen)
#   GET /pdf/demo.pdf             -> PDF binary (headless Chrome runs the same page)
#   GET /pdf/travel_orders/<ref>  -> model-backed preview (@travel_order)

class PdfController < FrontendController
  layout :pdf
  helper :pdf

  allow :get
  def call
    verify_access!

    return render_pdf if nav.format == :pdf

    # The layout renders the download link as plain markup, so it needs the
    # canonical path - same one the signature is built over, not nav.path.
    @pdf_url = "#{pdf_path}.pdf"

    # Models are loaded in the router (pdf routes.rb); @<model> is already set.
    # auto_render prefixes the view dir (:pdf) and reads the route cursor, which
    # the `map 'pdf' do` scope already advanced past the mount segment.
    auto_render
  end

  # Seconds a signed URL stays valid; covers Chrome start plus page load.
  SIGNATURE_TTL ||= 120

  # HMAC over the canonical (format-less) path and its expiry. Lets the
  # unauthenticated headless browser fetch the HTML page PdfGenerator prints.
  def self.sign(path, expires)
    OpenSSL::HMAC.hexdigest('SHA256', Lux.config.secret.to_s, "#{path}|#{expires.to_i}")
  end

  private

  # Canonical, format-less path for the signature. Reads nav.source_path so the
  # value is stable regardless of what load_models or app filters did to nav.path.
  def pdf_path
    '/' + nav.source_path.join('/')
  end

  # Render the current page to a PDF by pointing the headless browser at our own
  # signed HTML URL and streaming the result.
  def render_pdf
    path    = pdf_path
    expires = Time.now.to_i + SIGNATURE_TTL
    # Configured host, not the request's Host header: the server's own Chrome
    # fetches this URL, so it must never be steerable by the client.
    url = Url.new(Lux.config.host).path(path).qs(:s, self.class.sign(path, expires)).qs(:e, expires).to_s
    pdf = PdfGenerator.generate_pdf(url)

    response.headers['content-type']        = 'application/pdf'
    response.headers['content-disposition'] = %(attachment; filename="#{nav.source_path.last}.pdf")
    response.body pdf
  end

  def verify_access!
    return if user

    sig     = params[:s].to_s
    expires = params[:e].to_i
    ok = nav.format != :pdf && sig.present? && expires >= Time.now.to_i &&
      Rack::Utils.secure_compare(sig, self.class.sign(pdf_path, expires))
    raise Lux.error.not_found('Not found') unless ok
  end
end
