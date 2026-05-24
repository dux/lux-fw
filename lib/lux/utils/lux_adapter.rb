module Lux
  # Lux.crypt -> Lux::Utils::Crypt
  # Global crypto primitive with no per-request bindings. For IP-bound,
  # short-lived tokens use Lux.current.encrypt / Lux.current.decrypt instead.
  def crypt
    Lux::Utils::Crypt
  end

  # Lux.url('https://...') -> new Lux::Utils::Url
  # Lux.url                -> Url of current request (requires Lux.current)
  def url str = nil
    Lux::Utils::Url.new(str || Lux.current.request.url)
  end
end
