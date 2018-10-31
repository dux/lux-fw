# frozen_string_literal: true

# 2xx - Success            4xx / 5xx - Error     3xx - Redirection
# 200 OK                   400 Bad Request       301 Moved
# 201 Created              401 Unauthorized      302 Found
# 203 Partial Information  402 Payment Required  304 Not Modified
# 204 No response          403 Forbidden
# 404 Not Found
# 500 Internal Server Error
# 503 Service Unavailable

class Lux::Api
  attr_accessor :message, :response

  class_callback :before
  class_callback :after

  class << self
    # public mount method for router
    def call path, opts={}
      if path.is_a?(Symbol)
        # TestApi.call(:foo, email: '...')
        new.call path, opts
      else
        # Lux::Api.call([:user, :profile], email: '...' )
        return error 'Unsupported API call' if !path[1] || path[3]

        if path[2]
          opts[:_id] = path[1]
          path[1] = path[2]
        end

        run path[0], path[1], opts
      end
    end

    # public method for running actions on global class
    # use as Lux::Api.run 'users', 'show', { email:'rejotl@gmail.com' }
    # safe create api class and fix params
    def run klass, action, params={}
      params.delete_if{ |el| [:captures, :splat].index(el.to_sym) }

      action = action.to_s.sub(/[^\w_]/,'')

      class_name = klass.to_s.classify

      if params[class_name.underscore]
        begin
          params.merge! params.delete(class_name.underscore)
        rescue
          return error "#{$!.message}. Domain value is probably not hash, invalid parameter #{class_name.underscore}"
        end
      end

      for k,v in params
        params[k] = params[k].gsub('<','&lt;').gsub('>','&gt;').gsub(/\A^\s+|\s+\z/,'') if v.kind_of?(String)
      end

      begin
        klass = (klass.singularize.camelize+'Api').constantize
      rescue
        return error "API #{klass} not found"
      end

      klass.new.call(action.to_sym, params)
    end

    def error message
      Lux::Api::Response.error message
    end
  end

  ###

  def call action, params={}
    begin
      rescued_call action, params
    rescue Lux::Api::Error => e
      response.error e.message if e.message.to_s != 'false'
    rescue => e
      on_error(e)
    end

    puts response.render.pretty_generate if Lux.config(:log_to_stdout)

    response.render
  end

  # internal method for running actions
  # UserApi.new.call(:login, { email:'', pass:'' })
  def rescued_call action, params={}
    @response   = Lux::Api::Response.new
    @params     = params
    @action     = action
    @class_name = self.class.to_s.sub(/Api$/,'')

    error("Protected action call") if [:call, :rescued_call, :params, :error].index action
    error("Action #{action} not found in #{self.class.to_s}") unless respond_to? action

    # load default object
    if @params[:_id]
      eval "@object = @#{@class_name.underscore} = #{@class_name}[@params[:_id].to_i]"
      @params.delete(:_id)
    end

    @method_attr = self.class.method_attr[action] || {}

    return if response.errors?

    # execte api call and verify params if possible
    Object.class_callback :before, self
    response.data = send(action) unless response.errors?
    Object.class_callback :after, self unless response.errors?
  end

  def params
    @params
  end

  def error what=nil
    raise Lux::Api::Error.new(what || 'false')
  end

  def message what
    response.message = what
  end

  def current
    Lux.current
  end

  # default after block, can be overloaded
  def after
    return unless Lux.current

    response.meta :ip, Lux.current.request.ip
    response.meta :user, Lux.current.var.user ? Lux.current.var.user.email : nil
    response.meta :http_status, Lux.current.response.status(200)
  end

  def on_error error
    response.meta :error_key, Lux.error.log(error)
    response.meta :error_class, error.class.to_s
    response.error error.message
  end

end

ApplicationApi ||= Class.new Lux::Api




