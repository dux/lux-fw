require 'net/http'
require 'json'

# Framework-agnostic AuthCog client: builds the central-auth URL for a relying
# host and exchanges a single-use callback hash for the released identity.
#
# AuthcogController (a Lux app) and any standalone Rack/Sinatra server that
# needs the same handoff without a Lux::Controller both use this, so the URL
# shape and the exchange error mapping live in one place.
module Authcog
  class Error < StandardError; end

  DEFAULT_REALM ||= 'auth'

  module_function

  def realm
    Lux.config[:authcog_realm] || DEFAULT_REALM
  end

  # Absolute central-auth endpoint for `host` (and `port` for local/dev hosts).
  def auth_url host, port = nil, realm: nil
    realm = realm || Authcog.realm
    path  = "/domain:#{host}"
    path += "/port:#{port}" if port
    "https://#{realm}.authcog.com#{path}"
  end

  # Exchange a single-use callback hash server-side for
  # { email:, name:, avatar:, provider: }. Raises Authcog::Error on any
  # non-200; callers map it to their own error type.
  def exchange callback, host:, port: nil, realm: nil
    uri = URI("#{auth_url(host, port, realm: realm)}?user=#{callback}")
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.get(uri.request_uri)
    end

    case res.code.to_i
    when 200 then JSON.parse(res.body, symbolize_names: true)
    when 404 then raise Error, 'AuthCog callback unknown - expired session?'
    when 410 then raise Error, 'AuthCog callback already used or expired'
    else raise Error, "AuthCog exchange failed (#{res.code})"
    end
  end
end
