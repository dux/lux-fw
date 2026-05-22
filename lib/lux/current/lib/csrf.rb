# CSRF token surface on Lux::Current.
#
# Token is a 6-character random string stored in the session under :_csrf.
# Same value for the lifetime of the session; generated lazily on first read.
#
#   lux.session[:_csrf]   # raw token from session (or nil before first read)
#   lux.csrf              # lazy generate+persist; safe to call from anywhere
#   lux.csrf_valid?       # check incoming request submitted the right token
#
# Auto-checked by Application#render_base for non-GET requests that aren't
# Bearer-authenticated. Use lux.csrf in templates to render the hidden field:
#
#   <input type="hidden" name="_csrf" value="<%= lux.csrf %>">

module Lux
  class Current
    SESSION_CSRF_KEY ||= :_csrf

    # Returns the session's CSRF token, generating one on first read.
    def csrf
      @session[SESSION_CSRF_KEY] ||= Lux::Utils::Crypt.random(6)
    end

    # True if the incoming request submitted a token that matches the session.
    # Reads from the _csrf form param first, then X-CSRF-Token header.
    # Constant-time compare to avoid timing leaks.
    def csrf_valid?
      expected = @session[SESSION_CSRF_KEY].to_s
      return false if expected.empty?

      submitted = @request.params['_csrf'].to_s
      submitted = @request.env['HTTP_X_CSRF_TOKEN'].to_s if submitted.empty?
      return false if submitted.empty?

      ::Rack::Utils.secure_compare(expected, submitted)
    end

    # Verbs that never need CSRF (read-only).
    CSRF_SAFE_METHODS ||= %w[GET HEAD OPTIONS].freeze

    # Should the auto-check fire for this request?
    # Skip safe verbs. Skip Bearer-authenticated requests (not CSRF-vulnerable).
    def csrf_required?
      return false if CSRF_SAFE_METHODS.include?(@request.request_method)
      return false if bearer_token
      true
    end
  end
end
