# handy :)
# renders full pages and exposes page object (req, res) in yiled
# for easy and powerful testing
# Hash :qs, Hash :post, String :method, Hash :cookies, Hash :session
# https://github.com/rack/rack/blob/master/test/spec_request.rb

Lux::Application.class_eval do
  def self.render path='/mock', in_opts={}, &block
    allowed_opts = [:qs, :post, :method, :session, :cookies]
    in_opts.keys.each { |k| die "#{k} is not allowed as opts param. allowed are #{allowed_opts}" unless allowed_opts.index(k) }

    opts = {}

    if in_opts[:post]
      opts[:query_string] = in_opts[:post]
      opts[:request_method] = :post
    else
      opts[:query_string] = in_opts[:qs] || {}
      opts[:request_method] ||= in_opts[:method] || :get
    end

    opts[:request_method] = opts[:request_method].to_s.upcase
    opts[:query_string] = opts[:query_string].to_query if opts[:query_string].class.to_s == 'Hash'

    if path[0,4] == 'http'
      parsed = URI.parse(path)
      opts[:server_name] = parsed.host
      opts[:server_port] = parsed.port
      path = '/'+path.split('/', 4).last
    end

    env = Rack::MockRequest.env_for(path)
    env[:input] = opts[:post] if opts[:post]
    for k,v in opts
      env[k.to_s.upcase] = v
    end

    page = Lux::Current.new(env)
    Lux.current.session.merge!(in_opts[:session]) if in_opts[:session]

    if block_given?
      return Lux.app.new.instance_exec &block
    end

    response = Lux.current.response.render

    body = response[2].join('')
    body = JSON.parse body if response[1]['content-type'].index('/json')

    {
      time: response[1]['x-lux-speed'],
      status: response[0],
      headers: response[1],
      session: Lux.current.session,
      body: body
    }.h
  end
end