class AdminController < FrontendController
  include ControllerAutoLoader

  layout :admin

  allow :get, :post
  def call
    auto_export_var lux.route.root, nav.ref, :update if nav.ref
    tpl = auto_find_template nav.path
    render tpl
  end
end
