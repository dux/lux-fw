# response.header 'x-blah', 123
# response.max_age = 10
# response.public  = true
# response.status  = 500
class Lux::Response
  # define in seconds, how long should page be accessible in client cache
  # if defined, cache becomes public and can be cache by proxies
  # use with care.only for static resources and
  attr_reader :max_age

  attr_accessor :body, :headers, :cookies, :content_type, :status, :cookie_multidomain, :cookie_domain

  def initialize
    @render_start = Time.monotonic
    @headers      = Lux::Response::Header.new
    @max_age      = 0
  end

  def current
    Lux.current
  end

  def header name, value=:_
    @headers[name] = value if value != :_
    @headers[name]
  end

  def max_age= age
    @max_age = age.to_i
  end

  def etag *args
    unless @headers['etag']
      args.push current.request.url

      key = '"%s"' % Lux.cache.generate_key(args)
      key = 'W/%s' % key unless max_age > 0

      @headers['etag'] = key
    end

    if current.request.env['HTTP_IF_NONE_MATCH'] == @headers['etag']
      @status = 304
      @body   = 'not-modified'
      true
    else
      false
    end
  end

  def status num=nil
    return @status unless num
    raise 'Bad status value [%s]' % num unless num.is_numeric?

    @status ||= num
    @status
  end
  alias :status= :status

  def halt status=nil, msg=nil
    @status = status || 400
    @body   = msg if msg

    throw :done
  end

  def body what=nil
    @body ||= what

    if @body && block_given?
      @body = yield @body
      Lux.error 'Lux.current.response.body is not a string (bad current.response.body filter)' unless @body.is_a?(String)
    end

    @body
  end
  alias :body= :body

  def body! what
    @body = what
  end

  def content_type type=nil
    return @content_type unless type

    # can be set only once
    return @content_type if @content_type

    type = 'application/json' if type == :json
    type = 'text/plain' if type == :text
    type = 'text/html' if type == :html

    raise 'Invalid page content-type %s' % type if type === Symbol

    @content_type = type
  end

  def content_type= type
    content_type type
  end

  def flash message=nil
    @flash ||= Flash.new current.session[:lux_flash]

    message ? @flash.error(message) : @flash
  end

  def redirect where=nil, opts={}
    return @headers['location'] unless where

    @status = opts.delete(:status) || 302
    opts.map { |k,v| flash.send(k, v) }

    @headers['location']   = where.index('//') ? where : "#{current.host}#{where}"
    @headers['access-control-expose-headers'] ||= 'Location'

    @body = %[redirecting to #{@headers['location']}\n\n#{opts.values.join("\n")}]

    throw :done
  end

  def permanent_redirect where
    redirect where, status:301
  end

  # auth { |user, pass| [user, pass] == ['foo', 'bar'] }
  def auth relam=nil
    if auth = current.request.env['HTTP_AUTHORIZATION']
      credentials = auth.to_s.split('Basic ', 2)[1].unpack("m*").first.split(':', 2)
      return true if yield *credentials
    end

    status 401
    header('WWW-Authenticate', 'Basic realm="%s"' % relam.or('default'))
    body = ErrorCell.unauthorized('HTTP 401 Authorization needed')

    false
  end

  def write_response_body
    unless @body
      @status = 404
      @body = Lux.error 'Document not found'
    end

    # respond as JSON if we recive hash
    if @body.kind_of?(Hash)
      @body = Lux.dev? ? JSON.pretty_generate(@body) : JSON.generate(@body)

      if current.request.params[:callback]
        @body = "#{current.request.params[:callback]}(#{ret})"
        @content_type ||= 'text/javascript'
      else
        @content_type ||= 'application/json'
      end

      @body += "\n"
    else
      # if somebody sets @content_type, respect that
      @body = @body.to_s unless @body.kind_of?(String)
      @content_type ||= 'text/plain' if @body[0,1] != '<'
      @content_type ||= 'text/html'
    end
  end

  def write_response_header
    domain =
      if cookie_domain
        cookie_domain
      elsif cookie_multidomain && current.domain.index('.')
        ".#{current.domain}"
      else
        current.request.host
      end

    # cache-control
    @headers['cache-control'] ||= Proc.new do
      cc      = ['max-age=%d' % max_age]

      if max_age > 0
        cc.push 'public, no-cache'
      else
        cc.push 'private, must-revalidate'
      end

      cc.join(', ')
    end.call

    current.session[:lux_flash] = flash.to_h

    # dont annd cookies to public pages (images, etc..)
    add_cookies = true
    add_cookies = false if @headers['cache-control'].index('public')

    if add_cookies
      encrypted = Crypt.encrypt(current.session.to_json)

      if current.cookies[Lux.config.session_cookie_name] != encrypted
        @headers['set-cookie']  = "#{Lux.config.session_cookie_name}=#{encrypted}; Expires=#{(Time.now+1.month).utc}; Path=/; Domain=#{domain};"
      end
    end

    etag(@body) if current.request.request_method == 'GET'

    @headers['x-lux-speed']     = "#{((Time.monotonic - @render_start)*1000).round(1)} ms"
    @headers['content-type']  ||= "#{@content_type}; charset=utf-8"
    @headers['content-length']  = @body.bytesize
    # if "no-store" is present then HTTP_IF_NONE_MATCH is not sent from browser
  end

  def write_response
    write_response_body
    write_response_header

    @status ||= 200
    Lux.log " #{@status}, #{@headers['x-lux-speed']}"

    if ENV['LUX_PRINT_ROUTES']
      print '* Finished route print '
      puts @status == 404 ? 'without a match'.red : 'with a match'.green
      exit
    end

    [@status, @headers.to_h, [@body]]
  end

  def render
    Lux.log "\n#{current.request.request_method.white} #{Lux.current.request.path.white}"

    Lux::Config.live_require_check! if Lux.config(:auto_code_reload)

    Lux::Application.new.main

    write_response
  end

end
