# Seed Lux::Boot::STARTED_AT before requiring loader so amazing_print /
# sequel / etc. require-time is counted. Defined here (not in boot/boot.rb)
# because loader.rb pulls in those heavy gems before boot/boot.rb runs.
module Lux
  module Boot
    STARTED_AT ||= Time.now
  end
end

require_relative './lux/loader'
