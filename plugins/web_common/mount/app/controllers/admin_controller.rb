class AdminController < FrontendController
  include Lux::Controller::Auto

  layout :admin

  allow :get
  def call
    nav.load_models.each { |o| o.can.update! }
    tpl = auto_find_template nav.path
    render tpl
  end
end
