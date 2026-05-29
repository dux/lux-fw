class AdminController < FrontendController
  include Lux::Controller::Auto

  layout :admin

  allow :get
  def call
    auto_export_var lux.route.root, nav.ref, :update if nav.ref
    tpl = auto_find_template nav.path
    render tpl
  end
end
