# vars
# Lux.config.session_cookie_name
# Lux.config.session_cookie_max_age

# IMPORTANT - it is probably not a bug!
# If you have issues with cookies and sessions, try annonymous window and check info on set headers
# sometimes there is a bug there and cookie will not be set because of http https issues

module Lux
  class Current
    class Session
      attr_reader :hash, :cookie_name

      def initialize request
        # how long will session last if BROWSER or IP change
        Lux.config[:session_forced_validity] ||= 15.minutes.to_i
        Lux.config[:session_cookie_max_age]  ||= 1.month.to_i

        # name of the session cookie
        @cookie_name = Lux.config[:session_cookie_name] ||= 'lux_' + Crypt.sha1(Lux.config.secret)[0,4].downcase
        @cookie_name += "_#{request.port}" # we do not want http and https cookie name conflicts
        @request     = request
        @hash        = JSON.parse(Crypt.decrypt(request.cookies[@cookie_name] || '{}')) rescue {}

        security_check
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

      def generate_cookie
        encrypted = Crypt.encrypt(@hash.to_json)

        if @request.cookies[@cookie_name] != encrypted
          cookie_domain = Lux.current.var[:lux_cookie_domain] || Lux.current.nav.domain

          cookie = []
          cookie.push [@cookie_name, encrypted].join('=')
          cookie.push 'Max-Age=%s' % (Lux.config.session_cookie_max_age)
          cookie.push "Path=/"
          cookie.push "Domain=#{cookie_domain}"
          cookie.push "secure" if Lux.current.request.url.start_with?('https:')
          cookie.push "HttpOnly"
          cookie.push "SameSite=Lax"

          cookie.join('; ')
        else
          nil
        end
      end

      def merge! hash={}
        @hash.keys.each { |k| self[k] = @hash[k] }
      end

      def keys
        @hash.keys
      end

      def to_h
        @hash
      end

      def security_string
        base = @request.env['HTTP_CF_IPCOUNTRY'] || Lux.current.ip.split('.').first(3).join('.')
        base + @request.env['HTTP_USER_AGENT'].to_s
      end

      private

      def security_check
        key   = '_c'
        check = Crypt.sha1(security_string)[0, 5]

        # force type array
        @hash.delete(key) unless @hash[key].class == Array

        # allow 10 mins delay for IP change
        if @hash[key] && (@hash[key][0] != check && @hash[key][1].to_i < Time.now.to_i - Lux.config.session_forced_validity)
          @hash = {}
        end

        # add new time stamp to every request
        @hash[key] = [check, Time.now.to_i]
      end
    end
  end
end

