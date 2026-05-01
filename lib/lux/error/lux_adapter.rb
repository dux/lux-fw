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

  # Proxy that exposes named shortcuts. Each method delegates back to Lux.error
  # with the matching status code, so the call stack stays uniform.
  module ErrorProxy
    extend self
    HTTP_ERROR_SHORTCUTS.each do |name, code|
      define_method(name) { |msg = nil| Lux.error code, msg }
    end
  end

  # Canonical raise-with-status helper.
  #
  #   Lux.error 404                 # status 404, message defaults to "Not Found"
  #   Lux.error 404, 'custom'       # status 404, custom message
  #   Lux.error 'generic'           # status 400, custom message
  #   Lux.error                     # returns ErrorProxy for chaining
  #   Lux.error.not_found('msg')    # equivalent to Lux.error 404, 'msg'
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
    Lux.log " Lux.error #{code} at #{Lux.app_caller}" if Lux.env.log?

    raise Lux::Error.new(message)
  end
end
