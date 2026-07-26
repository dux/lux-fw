class AdminController < FrontendController
  layout :admin

  allow :get
  def call
    nav.load_models.each { |o| o.can.update! }
    # auto_render prefixes the view dir (:admin) and reads the route cursor,
    # so a missing template raises a proper 404 instead of rendering nothing.
    auto_render
  end
end
