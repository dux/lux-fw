# response.header 'x-blah', 123
# response.max_age = 10
# response.public  = true
# response.status  = 500
class Lux::Response
  # define in seconds, how long should page be accessible in client cache
  # if defined, cache becomes public and can be cache by proxies
  # use with care.only for static resources and
  attr_reader :max_age, :render_start
  attr_accessor :headers, :cookies, :content_type, :status

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

  # http 103
  def early_hints link=nil, type=nil
    @early_hints ||= []
    @early_hints.push [link, type] if type && !@early_hints.include?(link)
    @early_hints
  end

  def etag *args
    unless @headers['etag']
      args.push current.request.url

      key = '"%s"' % Lux.cache.generate_key(args)
      key = 'W/%s' % key unless max_age > 0

      @headers['etag'] = key
    end

    if !@body && current.request.env['HTTP_IF_NONE_MATCH'] == @headers['etag']
      status 304
      body   'not-modified'
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

  def body body_data=nil, status=nil
    @status = status      if status
    @body   = body_data   if body_data
    @body   = yield @body if block_given?
    throw :done if @body
    @body
  end
  alias :body= :body

  def body?
    !!@body
  end

  def content_type in_type=nil
    return @content_type unless in_type

    if in_type.is_a?(Symbol)
      type = Lux::Response::File::MIMME_TYPES[in_type]
      raise ArgumentError.new('Bad content type: %s' % in_type) unless type
    else
      type = in_type
    end

    @content_type = type
  end

  def content_type= type
    content_type type
  end

  def flash message=nil
    @flash ||= Flash.new current.session[:lux_flash]

    message ? @flash.error(message) : @flash
  end

  def send_file file, opts={}
    ::Lux::Response::File.new(file, opts).send
  end

  # redirect_to '/foo'
  # redirect_to :back, info: 'bar ...'
  def redirect_to where, opts={}
    opts   = { info: opts } if opts.is_a?(String)
    where  = current.request.env['HTTP_REFERER'].or('/') if where == :back
    where  = "#{current.request.path}#{where}" if where[0,1] == '?'
    where  = current.host + where unless where.include?('://')

    # local redirect
    if where.include?(current.host)
      redirect_var = Lux.config.redirect_var || :_r

      url = Url.new where
      url[redirect_var] = current.request.params[redirect_var].to_i + 1

      where =
        if opts.delete(:silent)
          url.delete redirect_var
          url.to_s
        else
          url[redirect_var] > 3 ? '/' : url.to_s
        end
    end

    @status = opts.delete(:status) || 302
    opts.map { |k,v| flash.send(k, v) }

    @body = %[redirecting to #{where}\n\n#{opts.values.join("\n")}]

    @headers['location'] = where
    @headers['access-control-expose-headers'] ||= 'Location'

    throw :done
  end

  def permanent_redirect_to where
    redirect_to where, status:301
  end

  # auth { |user, pass| [user, pass] == ['foo', 'bar'] }
  def auth relam=nil
    if auth = current.request.env['HTTP_AUTHORIZATION']
      credentials = auth.to_s.split('Basic ', 2)[1].unpack("m*").first.split(':', 2)
      return true if yield *credentials
    end

    status 401
    header('WWW-Authenticate', 'Basic realm="%s"' % relam.or('default'))
    body 'HTTP 401 Authorization needed'
    throw :done
  end

  def write_response_body
    unless @body
      @status = 204
      @body = 'Lux HTTP ERROR 204: NO CONTENT'
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
    # cache-control
    @headers['cache-control'] ||= Proc.new do
      cc = ['max-age=%d' % max_age]
      cc.push max_age > 0 ? 'public, no-cache' : 'private, must-revalidate'
      cc.join(', ')
    end.call

    current.session[:lux_flash] = flash.to_h

    # dont annd cookies to public pages (images, etc..)
    unless @headers['cache-control'].index('public')
      cookie = current.session.generate_cookie
      @headers['set-cookie'] = cookie if cookie
    end

    etag(@body) if current.request.request_method == 'GET'

    @headers['x-lux-speed']     = "#{((Time.monotonic - @render_start)*1000).round(1)}ms"
    @headers['content-type']  ||= "#{@content_type}; charset=utf-8"
    @headers['content-length']  = @body.bytesize.to_s

    # if "no-store" is present then HTTP_IF_NONE_MATCH is not sent from browser
  end

  def render
    write_response_body
    write_response_header

    @status ||= 200
    Lux.log " #{@status}, #{@headers['x-lux-speed']}"

    [@status, @headers.to_h, [@body]]
  end

  def render_inline body:, title: nil
    self.body %{<html>
        <head>
          <title>#{title || 'Lux info page'}</title>
          <style>
            body { font-size: 14pt; font-family: sans-serif;}
            div.box { border: 1px solid #ddd; padding: 10px 10px 1px 10px; background-color: #fff; margin-bottom: 10px; }
          </style>
        </head>
        <body style="margin: 20px 20px 20px 140px; background-color:#eee;">
          <img src="https://i.imgur.com/Zy7DLXU.png" style="width: 100px; position: absolute; margin-left: -120px;" />
          #{body}
        </body>
      </html>}
  end
end
