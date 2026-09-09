# Convention routed through Lux::Controller::Auto (mounted as `promo#auto`):
# every public page is a template under ./app/views/promo, no action needed.

class PromoController < FrontendController
  views :promo
end
