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
  # exceptions - and `on_log { |err| }` to send them elsewhere.
  module ErrorProxy
    extend self
    LOGGED_FLAG ||= :@_lux_error_logged

    # keyed by the block's source location, so a re-run registration
    # replaces itself instead of reporting twice
    REPORTERS ||= {}

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

      if Lux.debug?
        begin
          Lux.log "#{Lux.app_caller || 'unknown'} - #{exception.class}: #{exception.message}"
        rescue StandardError
          nil
        end
      end

      REPORTERS.each_value do |reporter|
        reporter.call(exception)
      rescue StandardError => reporter_error
        begin
          Lux.logger.error "Lux.error reporter failed: #{reporter_error.class}: #{reporter_error.message}"
        rescue StandardError
          nil
        end
      end
    end

    # Lux.error.on_log { |err| Sentry.capture_exception err }
    # Every reporter sees every logged error; one failing never stops the rest.
    def on_log &block
      raise ArgumentError, 'on_log requires a block' unless block
      REPORTERS[block.source_location] = block
    end

    private

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
    Lux.log " Lux.error #{code} at #{Lux.app_caller} - #{message}".colorize(:red) if Lux.debug?

    Lux::Error.new(message)
  end
end
