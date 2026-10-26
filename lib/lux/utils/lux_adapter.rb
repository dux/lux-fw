module Lux
  # Lux.crypt -> Lux::Utils::Crypt
  # Global crypto primitive with no per-request bindings. For IP-bound,
  # short-lived tokens use Lux.ctx.encrypt / Lux.ctx.decrypt instead.
  def crypt
    Lux::Utils::Crypt
  end

  # Lux.url('https://...') -> new Lux::Utils::Url
  # Lux.url                -> Url of current request (requires Lux.ctx)
  def url str = nil
    Lux::Utils::Url.new(str || Lux.ctx.request.url)
  end
end
