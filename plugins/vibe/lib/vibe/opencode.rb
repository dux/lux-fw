# Ruby-side probe of the headless `opencode serve` (health light). The browser
# talks to opencode through the Sinatra proxy (/oc/*), pinned to Vibe.root.

require 'net/http'
require 'uri'

module Vibe
  module Opencode
    module_function

    def url path, query = {}
      uri = URI(Vibe.oc_url + path)
      q   = URI.decode_www_form(uri.query.to_s).to_h.merge(query.transform_keys(&:to_s))
      q['directory'] = Vibe.root
      uri.query = URI.encode_www_form(q)
      uri
    end

    def get path, query = {}, timeout: 10
      request Net::HTTP::Get.new(url(path, query)), timeout: timeout
    end

    def request req, timeout: 10
      uri = req.uri
      res = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: timeout) { |http| http.request(req) }
      raise Error, 'opencode %s %s -> %s %s' % [req.method, uri.path, res.code, Vibe.first_line(res.body)] unless res.is_a?(Net::HTTPSuccess)

      ct = res['content-type'].to_s
      ct.include?('json') ? JSON.parse(res.body) : res.body
    rescue *Vibe::NET_ERRORS => e
      raise Error, 'opencode not reachable at %s (%s)' % [Vibe.oc_url, e.class]
    end

    def up?
      get('/global/health', timeout: 2)
      true
    rescue Error
      false
    end
  end
end
