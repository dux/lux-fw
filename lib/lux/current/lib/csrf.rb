# CSRF token surface on Lux::Current.
#
# Token is a 43-character random string (32 bytes) stored in the session under
# :_csrf, generated lazily on first read. It lives as long as the session, except
# that a sign-in replaces it (rotate_csrf!), so a token seen before login is dead.
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
      @session[SESSION_CSRF_KEY] ||= SecureRandom.urlsafe_base64(32)
    end

    # Drop the token; the next csrf read mints a fresh one. Call on sign-in.
    def rotate_csrf!
      @session.delete SESSION_CSRF_KEY
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
    # Skip requests that carry no session cookie: forgery works by making a
    # browser spend credentials it already holds, and there are none here. This is
    # what lets a webhook authenticated by a shared header token POST at all.
    def csrf_required?
      return false if CSRF_SAFE_METHODS.include?(@request.request_method)
      return false if bearer_token
      return false unless @session.cookie?
      true
    end
  end
end
