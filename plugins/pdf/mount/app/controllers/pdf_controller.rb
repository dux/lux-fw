# Reserved /pdf/ root (mirrors /admin/). Renders print-optimised pages from
# app/views/pdf/ in the :pdf layout, which paginates them into A4 pages with
# Paged.js - the very same engine used to render the downloadable PDF, so the
# on-screen preview and the PDF are identical.
#
# Access is dual-gated: logged-in users get the on-screen preview; the headless
# renderer fetches the page unauthenticated, so it is let in by a signed HMAC
# URL (PdfGenerator builds it via .sign).
#
#   GET /pdf/demo                 -> preview (Paged.js paginates on screen)
#   GET /pdf/demo.pdf             -> PDF binary (headless Chrome runs the same page)
#   GET /pdf/travel_orders/<ref>  -> model-backed preview (@travel_order)

class PdfController < FrontendController
  include Lux::Controller::Auto

  layout :pdf
  helper :pdf

  allow :get
  def call
    verify_access!

    return render_pdf if nav.format == :pdf

    # Models are loaded in the router (pdf routes.rb); @<model> is already set.
    tpl = auto_find_template(nav.path) or raise Lux.error.not_found 'PDF template not found'
    render tpl
  end

  # HMAC over the canonical (format-less) path. Lets the unauthenticated headless
  # browser fetch the HTML page that PdfGenerator turns into a PDF.
  def self.sign(path)
    Digest::SHA1.hexdigest("#{Lux.config.secret}#{path}")[0, 16]
  end

  private

  # Render the current page to a PDF by pointing the headless browser at our own
  # signed HTML URL (@pdf_path is the canonical path set by pdf routes.rb) and
  # streaming the result.
  def render_pdf
    url = Url.current.path(@pdf_path).qs(:s, self.class.sign(@pdf_path)).to_s
    pdf = PdfGenerator.generate_pdf(url)

    response.headers['content-type']        = 'application/pdf'
    response.headers['content-disposition'] = %(attachment; filename="#{nav.path.last}.pdf")
    response.body pdf
  end

  def verify_access!
    return if user
    sig = params[:s].to_s
    ok  = sig.present? && Rack::Utils.secure_compare(sig, self.class.sign(@pdf_path))
    raise Lux.error.not_found('Not found') unless ok
  end
end
