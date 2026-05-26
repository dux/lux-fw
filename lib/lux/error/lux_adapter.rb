module Lux
  HTTP_ERROR_SHORTCUTS ||= {
    bad_request:           400,
    unauthorized:          401,
    payment_required:      402,
    forbidden:             403,
    not_found:             404,
    method_not_allowed:    405,
    not_acceptable:        406,
    internal_server_error: 500,
    not_implemented:       501,
  }.freeze

  # Named shortcuts. Each method sets the HTTP status on the response
  # and returns a Lux::Error - the caller must `raise` it explicitly:
  #
  #   raise Lux.error.not_found('user missing')
  #
  # Also exposes `log(exception)` - the canonical hook for capturing
  # exceptions. Default is a no-op that warns. Plugins (e.g. admin_web)
  # redefine `Lux::ErrorProxy.log` to send errors to their store.
  module ErrorProxy
    extend self
    HTTP_ERROR_SHORTCUTS.each do |name, code|
      define_method(name) { |msg = nil| Lux.error code, msg }
    end

    def log(exception)
      Lux.log "Lux.error.log: error logger not assigned (#{exception.class}: #{exception.message})"
    end
  end

  # Canonical helper: set HTTP status on response, return a Lux::Error.
  # Caller is responsible for `raise`.
  #
  #   raise Lux.error 404                 # status 404, message "Not Found"
  #   raise Lux.error 404, 'custom'       # status 404, custom message
  #   raise Lux.error 'generic'           # status 400, custom message
  #   Lux.error                           # returns ErrorProxy for chaining
  #   raise Lux.error.not_found('msg')    # equivalent to raise Lux.error 404, 'msg'
  def error(*args)
    return ErrorProxy if args.empty?

    code, message =
      if args.first.is_a?(Integer)
        [args[0], args[1]]
      else
        [400, args[0]]
      end

    message ||= ::Rack::Utils::HTTP_STATUS_CODES[code] || 'Error'

    Lux.current.response.status code
    Lux.log " Lux.error #{code} at #{Lux.app_caller} - #{message}" if Lux.mode.debug?

    Lux::Error.new(message)
  end
end
