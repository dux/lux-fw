# vars
# Lux.config.session_cookie_name
# Lux.config.session_cookie_max_age
# Lux.config.session_cookie_domain
# Lux.config.session_ip_check

# IMPORTANT - it is probably not a bug!
# If you have issues with cookies and sessions, try annonymous window and check info on set headers
# sometimes there is a bug there and cookie will not be set because of http https issues

module Lux
  class Current
    class Session
      SEAL_PURPOSE  ||= 'session'
      REFRESH_AFTER ||= 1.day.to_i

      # one-time handoff to another host, see #transfer_token
      TRANSFER_PARAM   ||= '_lux_st'
      TRANSFER_PURPOSE ||= 'session_transfer'
      TRANSFER_TTL     ||= 60
      HANDOFF_PATH     ||= '/_lux_/handoff'
      HANDOFF_PURPOSE  ||= 'session_handoff'
      # per-host keys, rebuilt by the receiving host
      TRANSFER_SKIP    ||= ['_c', '_t', Dbsc::KEY, Dbsc::OFFERED]

      attr_reader :hash, :cookie_name

      def initialize request
        Lux.config[:session_cookie_max_age]    ||= 10.days.to_i

        # name of the session cookie, encodes Accept-Language for immediate invalidation
        base = Lux.config[:session_cookie_name] || 'lux'
        identity = request.env['HTTP_ACCEPT_LANGUAGE'].to_s
        @request     = request
        @cookie_name = cookie_prefix + base + '_' + Lux::Utils::Crypt.sha1(Lux.config.secret + identity)[0,6].downcase
        @cookie_name += "_#{request.port}" # we do not want http and https cookie name conflicts
        @raw_cookie  = request.cookies[@cookie_name]
        @hash        = Lux::Utils::Crypt.unseal(@raw_cookie, purpose: SEAL_PURPOSE)
        @hash        = {} unless @hash.is_a?(::Hash)
        @hash        = {} unless Dbsc.proven?(request, self)

        security_check

        # baseline for dirty tracking - after security_check so security writes don't count as dirt
        @original_hash = @hash.dup
        @forced_dirty  = false

        refresh_lifetime
      end

      # Did the request actually present a session cookie? Distinguishes a browser
      # carrying ambient credentials from a bare machine-to-machine call.
      def cookie?
        !@raw_cookie.nil?
      end

      def [] key
        @hash[key.to_s.downcase]
      end

      def []= key, value
        @hash[key.to_s.downcase] = value
      end

      def delete key
        @hash.delete key.to_s.downcase
      end

      # mark session as needing a fresh cookie even when hash didn't change
      def touch!
        @forced_dirty = true
      end

      # session changed since load (or never was persisted) ?
      def dirty?
        return true if @forced_dirty
        return true if @raw_cookie.nil?
        @hash != @original_hash
      end
      alias :changed? :dirty?

      def generate_cookie
        return nil unless dirty?

        # Sealed (AES-256-GCM), so the browser can neither read nor edit it, with
        # the same lifetime the browser gets. Max-Age alone is a client hint - a
        # copied cookie replays forever without a TTL inside the token.
        encrypted     = Lux::Utils::Crypt.seal(@hash, ttl: Lux.config[:session_cookie_max_age], purpose: SEAL_PURPOSE)

        cookie_domain = Lux.config[:session_cookie_domain]

        cookie = []
        cookie.push [@cookie_name, encrypted].join('=')
        cookie.push 'Max-Age=%s' % (Lux.config.session_cookie_max_age)
        cookie.push 'Path=/'
        cookie.push "Domain=#{cookie_domain}" if valid_cookie_domain?(cookie_domain)
        cookie.push 'Secure' if @request.ssl?
        cookie.push 'HttpOnly'
        cookie.push "SameSite=#{Lux.config[:session_cookie_same_site] || 'Lax'}"

        cookie.join('; ')
      end

      def merge! hash={}
        hash.each { |k, v| self[k] = v }
      end

      def keys
        @hash.keys
      end

      def to_h
        @hash
      end

      # country (CF-IPCountry) is hashed here, not in the cookie name, so geo binding is not observable.
      # UA (minus version numbers, so a browser update keeps the session) and country are treated
      # as fixed per device - any change wipes the session (re-auth). CF-* headers only survive
      # from a Cloudflare hop, see Lux::Current::Request.
      # session_ip_check binds the session to the exact IP - strict, breaks on wifi/cellular switch.
      def security_string
        string  = @request.env['HTTP_USER_AGENT'].to_s.gsub(/\d+/, '') + @request.env['HTTP_CF_IPCOUNTRY'].to_s
        string += Lux.current.ip if Lux.config[:session_ip_check]
        string
      end

      # Same-host link that mints the transfer token only when followed, so the
      # page holding it can sit open or in a public cache. The target URL is
      # sealed, so the endpoint hands sessions only to places the app linked.
      def handoff_link url
        '%s?to=%s' % [HANDOFF_PATH, Lux::Utils::Crypt.seal(url, purpose: HANDOFF_PURPOSE)]
      end

      # Target of a #handoff_link with a fresh transfer token, or nil for a
      # forged target or one outside the current domain.
      def handoff token
        url = Lux::Utils::Crypt.unseal(token.to_s, purpose: HANDOFF_PURPOSE)
        return unless url.is_a?(String)

        url    = Url.new(url)
        domain = Lux.current.nav.domain
        return unless url.host == domain || url.host.to_s.end_with?(".#{domain}")

        url.qs(TRANSFER_PARAM, transfer_token(url.host)).url
      end

      # Sealed one-time handoff of this session to `host`, minted by #handoff.
      # Bound to the browser check, so a leaked link is useless in another browser.
      def transfer_token host
        data = @hash.reject { |k, _| TRANSFER_SKIP.include?(k) }
        Lux::Utils::Crypt.seal(
          { 'data' => data, 'to' => host.to_s, 'c' => browser_check, 'n' => Lux::Utils::Crypt.uid(16) },
          ttl: TRANSFER_TTL, purpose: TRANSFER_PURPOSE
        )
      end

      # Merges a #transfer_token handed to this host. False for a forged,
      # expired, already used or foreign token, or one from another browser.
      # The used-token mark is not atomic; the browser check covers the race.
      def receive_transfer token
        t = Lux::Utils::Crypt.unseal(token.to_s, purpose: TRANSFER_PURPOSE)
        return false unless t.is_a?(::Hash) && t['to'] == @request.host && t['c'] == browser_check

        used = 'lux:session-transfer:%s' % t['n']
        return false if Lux.cache.get(used)

        Lux.cache.set used, 1, TRANSFER_TTL
        merge! t['data']
        true
      end

      private

      def browser_check
        Lux::Utils::Crypt.sha1(security_string)[0, 5]
      end

      # Browsers refuse a __Host- cookie that is not Secure, has a Domain, or a
      # Path other than /, so neither cookie can be planted from a subdomain or
      # over plain http. A shared session_cookie_domain allows only __Secure-.
      def cookie_prefix
        return '' unless @request.ssl?
        valid_cookie_domain?(Lux.config[:session_cookie_domain]) ? '__Secure-' : '__Host-'
      end

      # Reissue a day-old cookie, so the max_age window slides while the visitor
      # keeps coming back and a visitor gone longer than max_age is logged off.
      def refresh_lifetime
        now = Time.now.to_i
        return if @hash['_t'].to_i > now - REFRESH_AFTER

        @hash['_t'] = now
        touch!
      end

      # Don't emit Domain= for localhost or bare IP hosts.
      def valid_cookie_domain? domain
        return false if domain.nil? || domain.empty?
        return false if domain == 'localhost'
        return false if domain =~ /\A[\d.]+\z/        # IPv4
        return false if domain =~ /\A[0-9a-f:]+\z/i && domain.include?(':')   # IPv6
        true
      end

      def security_check
        key   = '_c'
        check = browser_check
        @hash = {} if @hash[key] && @hash[key] != check
        @hash[key] = check
      end
    end
  end
end
