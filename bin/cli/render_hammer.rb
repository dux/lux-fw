task :render do
  desc 'Render page via Lux.render: lux render /login -t TOKEN -s user_id=1 -i'
  needs :app
  opt :path,                                desc: 'Page path (positional)'
  opt :method,  alias: :m, default: 'get',  desc: 'HTTP method (get, post, put, patch, delete)'
  opt :params,  alias: :p, type: :array,    desc: 'Params: k=v&k=v (query for GET, body for others)'
  opt :session, alias: :s, type: :array,    desc: 'Session keys: k=v&k=v'
  opt :cookie,  alias: :c, type: :array,    desc: 'Cookies: k=v&k=v'
  opt :header,  alias: :H, type: :array,    desc: 'Headers: K=V&K=V'
  opt :token,   alias: :t,                  desc: 'Bearer token (sets Authorization header)'
  opt :body,    alias: :b, type: :boolean,  desc: 'Print body only (default)'
  opt :info,    alias: :i, type: :boolean,  desc: 'Print full info hash (status, time, headers, session)'

  proc do |opts|
    path = opts[:path]
    error 'Usage: lux render PATH [options]' unless path

    parse_pairs = ->(list) {
      Array(list).flat_map { |s| s.to_s.split('&') }.each_with_object({}) do |pair, h|
        k, v = pair.split('=', 2)
        h[k] = v.to_s
      end
    }

    header_to_env = ->(name) {
      'HTTP_%s' % name.to_s.upcase.tr('-', '_')
    }

    env_opts = {}
    parse_pairs.(opts[:header]).each { |k, v| env_opts[header_to_env.(k)] = v }
    env_opts['HTTP_AUTHORIZATION'] = 'Bearer %s' % opts[:token] if opts[:token]

    env = ::Rack::MockRequest.env_for(path, env_opts)

    render_opts = {
      method:   opts[:method].to_s.downcase.to_sym,
      params:   parse_pairs.(opts[:params]),
      session:  parse_pairs.(opts[:session]),
      cookies:  parse_pairs.(opts[:cookie])
    }

    data = Lux.app.new(env, render_opts).render_page

    if opts[:info]
      data[:body] = 'BODY length: %s kB' % (data[:body].to_s.length.to_f / 1024).round(1)
      puts data.to_h.to_jsonp
    else
      body = data[:body]
      puts body.is_a?(String) ? body : JSON.pretty_generate(body)
    end
  end
end
