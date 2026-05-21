# Sinatra web viewer for LuxException.
# Standalone with basic auth, or routed in Lux:
#
#   LuxExceptionWeb.password = 'secret'
#   map '/admin/sys-errors' => LuxExceptionWeb

require 'sinatra/base'

class LuxExceptionWeb < Sinatra::Base
  class << self
    attr_accessor :password
  end

  helpers do
    def prefix
      request.script_name
    end

    def time_ago(time)
      return '' unless time
      diff = Time.now - time
      case diff
      when 0..59 then "#{diff.to_i}s ago"
      when 60..3599 then "#{(diff / 60).to_i}m ago"
      when 3600..86399 then "#{(diff / 3600).to_i}h ago"
      else "#{(diff / 86400).to_i}d ago"
      end
    end

    def trim(str, n)
      s = str.to_s
      s.length > n ? s[0, n] + '...' : s
    end

    def h(text)
      Rack::Utils.escape_html(text.to_s)
    end
  end

  set :bind, '0.0.0.0'
  set :protection, false
  set :host_authorization, { allow_if: ->(_env) { true } }
  set :views, Lux.fw_root.join('plugins/exception_logger/views').to_s

  before do
    if self.class.password
      auth = Rack::Auth::Basic::Request.new(request.env)
      unless auth.provided? && auth.basic? && auth.credentials[1] == self.class.password
        headers['WWW-Authenticate'] = 'Basic realm="LuxException"'
        halt 401, 'Unauthorized'
      end
    end
  end

  get '/?' do
    @klass_filter = params[:klass]
    @user_filter  = params[:user]

    @users = LuxException.get_users
    @types = LuxException.get_error_types
    @list  = LuxException.get_list klass: @klass_filter, email: @user_filter
    @total = LuxException.size

    erb :index
  end

  get '/show' do
    @exp = LuxException.get_exp params[:uid]
    halt 404, 'Exception not found' unless @exp
    erb :show
  end

  post '/resolve' do
    exep = LuxException.first(uid: params[:uid])
    halt 404, 'Exception not found' unless exep
    exep.update is_resolved: true
    redirect "#{prefix}/show?uid=#{exep.uid}"
  end
end
