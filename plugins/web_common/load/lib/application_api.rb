# Base API class for all JSON API endpoints. Mounted at /api.
# Handles authentication (bearer token or session), JSON response formatting,
# error handling with exception logging, and collection pagination.

class ApplicationApi < Lux::Api
  mount_on '/api'

  auth do |bearer|
    bearer ||= params[:api_key]
    User.current ||= (User.first(api_key: bearer) if bearer)
  end

  before do |opts|
    # load user if token provided
    if !user && !opts[:unsafe]
      error [
        'You have to have user api session to perform this action',
        ('def info: you can mark api action as unsafe to allow anonymous usage' if Lux.env.dev?)
      ]
    end
  end

  after do
    Lux.log { response.render.to_jsonp }
  end

  after_auto_mount do |path|
    path.shift if path.first == 'api'
  end

  rescue_from do |error|
    # expected client faults (validation, permission, guest writes) aren't bugs -
    # return as JSON, don't persist. logging is guarded so a failed write (e.g. a
    # demo user tripping the guest hook inside the logger) can't escape and dump a trace.
    client = Lux::Api::Response.client_error? error
    Lux.error.log(error) rescue nil unless client

    response[:error_class] = error.class.name
    response.error error.message, status: (client ? 400 : 500)
  end

  ###

  def current
    Lux.current
  end

  def paginate list, in_opts = {}
    data = list.page **in_opts
    opts = data.paginate_opts
    url  = Url.new(Lux.current.request.url)

    opts[:previous] = opts[:page] > 1 ? url.qs(:page, opts[:page] - 1).to_s : false
    opts[:next]     = url.qs(:page, opts[:page] + 1).to_s if opts[:next]

    {
      paginate: opts,
      list: data.map(&:export),
    }
  end
end
