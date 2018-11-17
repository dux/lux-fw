# frozen_string_literal: true

# we need this for command line
Thread.current[:lux] ||= { cache: {} }

class Lux::Current
  # set to true if user is admin and you want him to be able to clear caches in production
  attr_accessor :can_clear_cache

  attr_accessor :session, :locale
  attr_reader   :request, :response, :nav

  def initialize env=nil
    env   ||= '/mock'
    env     = ::Rack::MockRequest.env_for(env) if env.is_a?(String)
    request = ::Rack::Request.new env

    # reset page cache
    Thread.current[:lux] = { cache:{}, page: self }

    @files_in_use = []
    @response     = Lux::Response.new
    @request      = request
    @session      = Lux::Current::Session.new request

    # remove empty paramsters in GET request
    if request.request_method == 'GET'
      for el in request.params.keys
        request.params.delete(el) if request.params[el].blank?
      end
    end

    # indiferent access
    request.instance_variable_set(:@params, request.params.h_wia) if request.params.keys.length > 0

    Lux::Current::EncryptParams.decrypt request.params
    ap request.params if request.post? && Lux.config(:log_to_stdout)

    @nav = Lux::Application::Nav.new request
  end

  # Domain part of the host
  def domain
    host = Lux.current.request.host.split('.')
    host_country = host.pop
    host_name    = host.pop
    host_name ? "#{host_name}.#{host_country}" : host_country
  end

  # Full host with port
  def host
    "#{request.env['rack.url_scheme']}://#{request.host}:#{request.port}".sub(':80','')# rescue 'http://locahost:3000'
  end

  # Current scope variables hash
  def var
    Thread.current[:lux][:var] ||= Hashie::Mash.new
  end

  # Cache data in current page
  def cache key
    data = Thread.current[:lux][:cache][key]
    return data if data
    Thread.current[:lux][:cache][key] = yield
  end

  # Set current.can_clear_cache = true in production for admins
  def no_cache?
    @can_clear_cache = true if Lux.dev?
    @can_clear_cache && @request.env['HTTP_CACHE_CONTROL'].to_s.downcase == 'no-cache' ? true : false
  end

  # Redirect from current page
  def redirect *args
    response.redirect *args
  end

  # Execute action once per page
  def once id=nil, data=nil, &block
    id ||= Digest::SHA1.hexdigest caller[0] if block

    @once_hash ||= {}
    return if @once_hash[id]
    @once_hash[id] = true

    block_given? ? yield : data
  end

  # Generete unique ID par page render
  def uid
    Thread.current[:uid_cnt] ||= 0
    "uid-#{Thread.current[:uid_cnt]+=1}"
  end

  # Add to list of files in use
  def files_in_use file=nil
    if block_given?
      return yield(file) unless @files_in_use.include?(file)
    end

    return @files_in_use unless file
    return unless Lux.config(:log_to_stdout)

    file = file.sub './', ''

    if @files_in_use.include?(file)
      true
    else
      @files_in_use.push file
      false
    end
  end
end

