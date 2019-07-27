# class for rendering full output pages

# page = Lux::Application::RenderPage.new '/', foo: 123
# page.post    = { ... }
# page.session = user_id: User.first.id
# page.render { City.current = City.first }
# page.response

class Lux::Application::RenderPage
  attr_reader :app
  attr_reader :proc_response
  attr_reader :response

  def initialize path, qs={}
    @opts = {}
    @path = path
    @opts[:query_string]   = qs
    @opts[:request_method] = :get
  end

  def post data
    @opts[:query_string]   = data
    @opts[:request_method] = :post
  end

  def session data
    @session = data
  end

  def cookies data
    @cookies = data
  end

  def render &block
    @opts[:request_method] = @opts[:request_method].to_s.upcase
    @opts[:query_string]   = @opts[:query_string].to_query if @opts[:query_string].is_a?(Hash)

    if @path[0, 4] == 'http'
      parsed = URI.parse(path)
      @opts[:server_name] = parsed.host
      @opts[:server_port] = parsed.port
      @path = '/' + path.split('/', 4).last
    end

    env = Rack::MockRequest.env_for(@path)
    env[:input] = @opts[:post] if @opts[:post]
    @opts.each { |k, v| env[k.to_s.upcase] = v }

    @current = Lux::Current.new(env)
    @current.session.merge!(@session) if @session

    @app = Lux::Application.new @current
    @proc_response = @app.instance_exec(&block) if block_given?

    out  = @app.render
    body = out[2].join('')
    body = JSON.parse body if out[1]['content-type'].index('/json')

    @response = {
      body:    body,
      time:    out[1]['x-lux-speed'],
      status:  out[0],
      session: @current.session.hash,
      headers: out[1]
    }.h

    @response[:proc_response] = @proc_response if @proc_response

    @response
  end
end

# renders full pages and exposes page object (req, res) in yiled
# for easy and powerful testing
# Hash :qs, Hash :post, String :method, Hash :cookies, Hash :session
# https://github.com/rack/rack/blob/master/test/spec_request.rb

# Lux.app.render('/admin') -> { status: 403, ... }
# Lux.app.render('/admin', session: { user_id: User.is_admin.first.id })
# {
#   time: '1ms'
#   status: 200,
#   headers: {...},
#   session: {...},
#   body: '<html> ...'
# }.h

class Lux::Application
  def self.render path='/mock', opts={}, &block
    opts = opts.to_opts :qs, :post, :method, :session, :cookies
    page = Lux::Application::RenderPage.new path, opts[:qs]
    page.session opts[:session] if opts[:session]
    page.cookies opts[:cookies] if opts[:cookies]
    page.post    opts[:post]    if opts[:post]
    page.render
  end
end