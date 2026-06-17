class DevController < FrontendController
  layout :dev
  helper :html

  before do
    nav.path.shift
  end
end
