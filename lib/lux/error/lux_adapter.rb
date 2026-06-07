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
  # exceptions. Override `log_custom(exception)` to persist errors elsewhere.
  module ErrorProxy
    extend self
    LOGGED_FLAG ||= :@_lux_error_logged

    HTTP_ERROR_SHORTCUTS.each do |name, code|
      define_method(name) { |msg = nil| Lux.error code, msg }
    end

    def log(exception)
      return unless exception
      already_logged = exception.instance_variable_defined?(LOGGED_FLAG) rescue false
      return if already_logged

      exception.instance_variable_set(LOGGED_FLAG, true) rescue nil

      # Lux::Error / Lux::Api::Error are deliberate HTTP control-flow signals
      # (403/404/422...), not bugs - don't dump a backtrace for them. Mirrors
      # the API layer's `unless is_a?(Lux::Api::Error)` guards and IGNORE list.
      unless expected_http_error?(exception)
        begin
          Lux.logger.error Lux::Error.format(exception, message: true)
        rescue StandardError
          nil
        end
      end

      if Lux.mode.debug?
        begin
          Lux.log "#{Lux.app_caller || 'unknown'} - #{exception.class}: #{exception.message}"
        rescue StandardError
          nil
        end
      end

      begin
        log_custom(exception)
      rescue StandardError => custom_error
        begin
          Lux.logger.error "Lux.error.log_custom failed: #{custom_error.class}: #{custom_error.message}"
        rescue StandardError
          nil
        end
      end
    end

    def log_custom(exception)
    end

    # Deliberate HTTP errors raised via `Lux.error CODE` (and the API
    # equivalent) - control flow, not crashes worth a backtrace dump.
    def expected_http_error?(exception)
      exception.is_a?(Lux::Error) ||
        (defined?(Lux::Api::Error) && exception.is_a?(Lux::Api::Error))
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
    Lux.log " Lux.error #{code} at #{Lux.app_caller} - #{message}".colorize(:red) if Lux.mode.debug?

    Lux::Error.new(message)
  end
end
