# Convention routed through Lux::Router#auto (mounted as `promo#auto`):
# every public page is a template under ./app/views/promo, no action needed.

class PromoRouter < FrontendRouter
  views :promo
end
