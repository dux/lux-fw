# Base API class for all JSON API endpoints. Mounted at /api.
# Handles authentication (bearer token or session), JSON response formatting,
# error handling with exception logging, and collection pagination.

class ApplicationApi < Lux::Api
  mount_on '/api'

  # non-`unsafe` endpoints need a user: bearer token, ?api_key= or the session
  auth do |bearer|
    User.current ||= UserSession.api_key_load(bearer || params[:api_key])
    User.current or response.error('You have to have user api session to perform this action', status: 401)
  end

  # after do
  #   Lux.log { response.render.to_jsonp }
  # end

  after_auto_mount do |path|
    path.shift if path.first == 'api'
  end

  ###

  def paginate list, in_opts = {}
    data = list.page **in_opts
    opts = data.paginate_opts
    url  = Url.new(Lux.ctx.request.url)

    opts[:previous] = opts[:page] > 1 ? url.qs(opts[:param], opts[:page] - 1).to_s : false
    opts[:next]     = url.qs(opts[:param], opts[:page] + 1).to_s if opts[:next]

    {
      paginate: opts,
      list: data.map(&:export),
    }
  end
end
