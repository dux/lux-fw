class DevRouter < FrontendRouter
  layout :dev
  before { raise Lux.error.not_found unless Lux.env.dev? }
end
