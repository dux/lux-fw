module Lux
  def secrets
    @lux_secrets ||= Proc.new do
      Lux::Secrets.new.to_h.to_ch :strict
    end.call
  end
end