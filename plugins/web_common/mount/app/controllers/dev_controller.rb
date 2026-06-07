class DevController < FrontendController
  include Lux::Controller::Auto

  layout :dev

  before do
    raise 'Not available' unless Lux.env.dev?
  end
end
