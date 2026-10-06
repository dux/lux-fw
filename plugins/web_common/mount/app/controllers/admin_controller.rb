class AdminController < FrontendController
  layout :admin

  # Plugin pages (/admin/plugins/*) load no models, so the per-model check in
  # #call alone would let anyone in.
  before do
    raise Lux.error.forbidden('Admin access required') unless user&.can&.admin?
  end

  allow :get
  def call
    nav.load_models.each { |o| o.can.update! }
    # auto_render prefixes the view dir (:admin) and reads the route cursor,
    # so a missing template raises a proper 404 instead of rendering nothing.
    auto_render
  end
end
