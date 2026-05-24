# Capture before requiring boot so amazing_print/sequel/etc. load time
# is counted in Lux.started_at. Defined here (not in lux.rb) because
# boot.rb pulls in heavy gems before lux.rb runs.
module Lux
  STARTED_AT ||= Time.now
end

require_relative './lux/boot'
