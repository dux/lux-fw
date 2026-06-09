class DevController < FrontendController
  layout :dev

  before do
    raise 'Not available' unless Lux.env.dev?
  end
end
