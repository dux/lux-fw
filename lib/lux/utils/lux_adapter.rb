module Lux
  # Lux.crypt -> Lux::Utils::Crypt
  # Global crypto primitive with no per-request bindings. For IP-bound,
  # short-lived tokens use Lux.current.encrypt / Lux.current.decrypt instead.
  def crypt
    Lux::Utils::Crypt
  end
end
