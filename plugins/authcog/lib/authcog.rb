require 'net/http'
require 'json'
require 'securerandom'

# Framework-agnostic AuthCog client: builds the central-auth URL for a relying
# host and exchanges a single-use callback hash for the released identity.
#
# AuthcogRouter (a Lux app) and any standalone Rack/Sinatra server that
# needs the same handoff without a Lux::Router both use this, so the URL
# shape and the exchange error mapping live in one place.
module Authcog
  class Error < StandardError; end

  DEFAULT_REALM ||= 'auth'

  module_function

  def realm
    Lux.config[:authcog_realm] || DEFAULT_REALM
  end

  # The request URL when it sits inside the domain of Lux.config.host
  # (subdomains included), else the configured host. A forged Host header
  # then cannot pick the domain a callback hash is exchanged for.
  #
  # On shared suffixes (herokuapp.com, github.io, ...) "same domain" trusts
  # strangers, so Lux.config[:authcog_hosts] (list of exact hosts), when set,
  # replaces the domain match.
  def relying_url request_url, home = Lux.config.host.to_s, hosts: Lux.config[:authcog_hosts]
    here = request_url.is_a?(Lux::Utils::Url) ? request_url : Lux::Utils::Url.new(request_url.to_s)
    home = Lux::Utils::Url.new(home.to_s)
    trusted = hosts ? Array(hosts).map { it.to_s.downcase }.include?(here.host.to_s.downcase) : here.domain == home.domain
    trusted ? here : home
  end

  # Mint a login challenge into `session[key]` (a Lux session or a Rack
  # session hash) and return it. Several are kept so sign-in links opened in
  # several tabs each stay usable.
  def mint_challenge session, key, limit: 4
    state = SecureRandom.urlsafe_base64(24)
    session[key] = (Array(session[key]) + [state]).last(limit)
    state
  end

  # True when `given` is one of the challenges held in `session[key]`, which
  # it then spends. Only a match is removed: a bogus state must not be able to
  # clear a real one and lock the visitor out of signing in.
  def claim_challenge session, key, given
    given = given.to_s
    return false if given.empty?

    held = Array(session[key])
    hit  = held.find { |s| Rack::Utils.secure_compare(s.to_s, given) }
    return false unless hit

    session[key] = held - [hit]
    true
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
  # non-200 or network failure; callers map it to their own error type.
  def exchange callback, host:, port: nil, realm: nil
    uri = URI("#{auth_url(host, port, realm: realm)}?user=#{callback}")
    res = begin
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 10) do |http|
        http.get(uri.request_uri)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      raise Error, "AuthCog unreachable (#{e.class})"
    end

    case res.code.to_i
    when 200
      begin
        JSON.parse(res.body, symbolize_names: true)
      rescue JSON::ParserError
        raise Error, 'AuthCog returned an unreadable identity'
      end
    when 404 then raise Error, 'AuthCog callback unknown - expired session?'
    when 410 then raise Error, 'AuthCog callback already used or expired'
    else raise Error, "AuthCog exchange failed (#{res.code})"
    end
  end
end
