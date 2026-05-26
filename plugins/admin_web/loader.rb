# LuxException - PG-backed exception logger with mountable web viewer
#
# Usage:
#   LuxException.add error
#   LuxException.get_list klass: 'RuntimeError'
#
# Overrides Lux::ErrorProxy.log so framework-internal `Lux.error.log err`
# calls capture exceptions into the LuxException table.

require 'digest'

require_relative 'lib/lux_exception'
require_relative 'lib/lux_exception_log'
require_relative 'lib/lux_exception_controller'

module Lux::ErrorProxy
  LOG_DEDUPE_KEY ||= 'lux:error_log:last_fingerprint'.freeze
  LOG_DEDUPE_TTL ||= 60

  def self.log(err)
    # Dedupe burst-repeats: if the last logged error has the same class and
    # was raised from the same app-level callsite, drop it. Uses Lux.cache
    # server directly so it works outside an HTTP request context too.
    root = Lux.root.to_s
    site = (err.backtrace || []).find { |l| l.start_with?(root) }
    fingerprint = "#{err.class}@#{site}"

    cache = Lux.cache.server rescue nil
    if cache
      return if (cache.get(LOG_DEDUPE_KEY) rescue nil) == fingerprint
      cache.set(LOG_DEDUPE_KEY, fingerprint, LOG_DEDUPE_TTL) rescue nil
    end

    LuxException.add err
  end
end
