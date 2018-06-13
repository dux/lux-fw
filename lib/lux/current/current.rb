# frozen_string_literal: true

# we need this for command line
Thread.current[:lux] ||= { cache: {} }

class Lux::Current
  # set to true if user is admin and you want him to be able to clear caches in production
  attr_accessor :can_clear_cache

  attr_accessor :session, :locale
  attr_reader   :request, :response, :nav, :is_first_response

  def initialize env=nil
    env   ||= '/mock'
    env     = ::Rack::MockRequest.env_for(env) if env.class == String
    request = ::Rack::Request.new env

    # reset page cache
    Thread.current[:lux] = { cache:{}, page: self }

    @files_in_use = []
    @response     = Lux::Response.new
    @request      = request
    @session      = {}

    @session = JSON.parse(Crypt.decrypt(request.cookies['__luxs'] || '{}')) rescue {}

    # check for session
    if Lux.dev? && request.env['HTTP_REFERER'] && request.env['HTTP_REFERER'].index(request.host) && @session.keys.length == 0
      puts "ERROR: There is no session set!".red
    end

    # hard sec, bind session to user agent and IP
    set_and_check_client_unique_hash

    @session = HashWithIndifferentAccess.new(@session)

    # indiferent access
    request.instance_variable_set(:@params, request.params.h_wia) if request.params.keys.length > 0

    # request.params.map { |k,_| request.params.delete(k) }

    Lux::Current::EncryptParams.decrypt request.params
    ap request.params if request.post? && Lux.config(:log_to_stdout)

    @nav = Lux::Application::Nav.new request
  end

  def files_in_use file=nil
    @files_in_use.push file if file && !@files_in_use.include?(file)
    @files_in_use
  end

  def set_and_check_client_unique_hash
    key   = '_c'
    check = Crypt.sha1(@request.ip.to_s+@request.env['HTTP_USER_AGENT'].to_s)[0,10]

    # force type array
    @session.delete(key) unless @session[key].class == Array

    # allow 5 mins delay for IP change
    @session = {} if @session[key] && (@session[key][0] != check && @session[key][1].to_i < Time.now.to_i - Lux.config.session_forced_validity)

    @is_first_response = !@session[key]

    # add new time stamp to every request
    @session[key] = [check, Time.now.to_i]
  end

  def domain
    host = Lux.current.request.host.split('.')
    host_country = host.pop
    host_name    = host.pop
    host_name ? "#{host_name}.#{host_country}" : host_country
  end

  def host
    "#{request.env['rack.url_scheme']}://#{request.host}:#{request.port}".sub(':80','')# rescue 'http://locahost:3000'
  end

  def var
    Thread.current[:lux][:var] ||= Hashie::Mash.new
  end

  # cache data in current page
  def cache key
    data = Thread.current[:lux][:cache][key]
    return data if data
    Thread.current[:lux][:cache][key] = yield
  end

  # set current.can_clear_cache = true in production for admins
  def no_cache?
    @can_clear_cache ||= true if Lux.dev?
    @can_clear_cache && @request.env['HTTP_CACHE_CONTROL'].to_s.downcase == 'no-cache' ? true : false
  end

  def redirect *args
    response.redirect *args
  end

  # execute action once per page
  def once id=nil, data=nil, &block
    id ||= Digest::SHA1.hexdigest caller[0] if block

    @once_hash ||= {}
    return if @once_hash[id]
    @once_hash[id] = true

    block_given? ? yield : data
  end

  def uid
    Thread.current[:uid_cnt] ||= 0
    "uid-#{Thread.current[:uid_cnt]+=1}"
  end

end

