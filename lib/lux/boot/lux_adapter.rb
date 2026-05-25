# Thin delegators on Lux. Actual orchestration lives in Lux::Boot.
# Kept so hosts can keep calling `Lux.boot!` from config/env.rb.

module Lux
  def boot!(&block)
    Lux::Boot.call(&block)
  end
  alias :boot :boot!

  def booted?
    Lux::Boot.booted?
  end

  def started_at
    Lux::Boot.started_at
  end
end
