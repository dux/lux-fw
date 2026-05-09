# LuxException - PG-backed exception logger with mountable web viewer
#
# Usage:
#   LuxException.add error
#   LuxException.get_list klass: 'RuntimeError'
#
# Auto-wires Lux.config.error_logger to LuxException.add

require 'digest'

require_relative 'lib/lux_exception'
require_relative 'lib/lux_exception_log'
require_relative 'lib/lux_exception_web'

Lux.config.error_logger = proc do |err|
  LuxException.add err
end
