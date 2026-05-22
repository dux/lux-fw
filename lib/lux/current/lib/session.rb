# vars
# Lux.config.session_cookie_name
# Lux.config.session_cookie_max_age
# Lux.config.session_security_refresh

# IMPORTANT - it is probably not a bug!
# If you have issues with cookies and sessions, try annonymous window and check info on set headers
# sometimes there is a bug there and cookie will not be set because of http https issues

module Lux
  class Current
    class Session
      attr_reader :hash, :cookie_name

      def initialize request
        # how long will session last if BROWSER or IP change
        Lux.config[:session_forced_validity]   ||= 15.minutes.to_i
        Lux.config[:session_cookie_max_age]    ||= 1.month.to_i
        # refresh the security timestamp at most once per N seconds (default 5 min)
        Lux.config[:session_security_refresh]  ||= 5.minutes.to_i

        # name of the session cookie, encodes Accept-Language and CF country for immediate invalidation
        base = Lux.config[:session_cookie_name] || 'lux'
        identity = request.env['HTTP_ACCEPT_LANGUAGE'].to_s + request.env['HTTP_CF_IPCOUNTRY'].to_s
        @cookie_name = base + '_' + Lux::Utils::Crypt.sha1(Lux.config.secret + identity)[0,6].downcase
        @cookie_name += "_#{request.port}" # we do not want http and https cookie name conflicts
        @request     = request
        @raw_cookie  = request.cookies[@cookie_name]
        @hash        = JSON.parse(Lux::Utils::Crypt.decrypt(@raw_cookie || '{}')) rescue {}

        security_check

        # baseline for dirty tracking - after security_check so security writes don't count as dirt
        @original_hash = @hash.dup
        @forced_dirty  = false
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

        encrypted     = Lux::Utils::Crypt.encrypt(@hash.to_json)
        return nil if encrypted == @raw_cookie

        cookie_domain = Lux.current.var[:lux_cookie_domain] || Lux.current.nav.domain

        cookie = []
        cookie.push [@cookie_name, encrypted].join('=')
        cookie.push 'Max-Age=%s' % (Lux.config.session_cookie_max_age)
        cookie.push 'Path=/'
        cookie.push "Domain=#{cookie_domain}" if valid_cookie_domain?(cookie_domain)
        cookie.push 'Secure' if Lux.current.request.url.start_with?('https:')
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

      def security_string
        Lux.current.ip + @request.env['HTTP_USER_AGENT'].to_s
      end

      private

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
        check = Lux::Utils::Crypt.sha1(security_string)[0, 5]

        # force type array
        @hash.delete(key) unless @hash[key].class == Array

        if @hash[key] && @hash[key][0] != check
          # IP or browser changed - check grace period from last valid request
          if @hash[key][1].to_i < Time.now.to_i - Lux.config.session_forced_validity
            @hash = {}
          end

          # don't update timestamp so grace period counts down from last matching request
          return
        end

        # refresh timestamp only periodically; otherwise leave hash untouched so cookie stays stable
        if !@hash[key] || @hash[key][1].to_i < Time.now.to_i - Lux.config.session_security_refresh
          @hash[key] = [check, Time.now.to_i]
        end
      end
    end
  end
end
