# vars
# Lux.config.session_cookie_name
# Lux.config.session_cookie_max_age
# Lux.config.session_cookie_domain

class Lux::Current::Session
  def initialize request
    # how long will session last if BROWSER or IP change
    Lux.config.session_forced_validity ||= 10.minutes.to_i

    # name of the session cookie
    @cookie_name = Lux.config.session_cookie_name ||= 'lux_' + Crypt.sha1(Lux.config.secret)[0,4].downcase
    @request     = request
    @session     = JSON.parse(Crypt.decrypt(request.cookies[@cookie_name] || '{}')) rescue {}

    # check for session
    # if Lux.dev? && request.env['HTTP_REFERER'] && request.env['HTTP_REFERER'].index(request.host) && @session.keys.length == 0
    #   puts "ERROR: There is no session set!".red
    # end

    security_check
  end

  def [] key
    @session[key.to_s.downcase]
  end

  def []= key, value
    @session[key.to_s.downcase] = value
  end

  def delete key
    @session.delete key.to_s.downcase
  end

  def generate_cookie
    encrypted = Crypt.encrypt(@session.to_json)

    if @request.cookies[@cookie_name] != encrypted
      cookie = []
      cookie.push [@cookie_name, encrypted].join('=')
      cookie.push 'Max-Age=%s' % (Lux.config.session_cookie_max_age || 1.week.to_i)
      cookie.push "Path=/"
      cookie.push "Domain=#{Lux.config.session_cookie_domain}" if Lux.config.session_cookie_domain
      cookie.push "secure" if Lux.config.host.include?('https:')
      cookie.push "HttpOnly"

      cookie.join('; ')
    else
      nil
    end
  end

  def merge! hash={}
    hash.keys.each { |k| self[k] = hash[k] }
  end

  def hash
    @session.dup
  end

  private

  def security_check
    key   = '_c'
    check = Crypt.sha1(@request.ip.to_s+@request.env['HTTP_USER_AGENT'].to_s)[0, 5]

    # force type array
    @session.delete(key) unless @session[key].class == Array

    # allow 10 mins delay for IP change
    @session = {} if @session[key] && (@session[key][0] != check && @session[key][1].to_i < Time.now.to_i - Lux.config.session_forced_validity)

    # add new time stamp to every request
    @session[key] = [check, Time.now.to_i]
  end
end