module Lux
  def secrets
    @lux_secrets ||= Proc.new do
      Lux::Secrets.new.to_h.to_hwia
    end.call
  end
end