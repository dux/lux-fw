# Thin client for the headless `opencode serve` HTTP API (v1 routes). Every call
# carries ?directory=<Vibe.root> so the server works on the harness checkout no
# matter where it was started. The browser talks to the same API through the
# Sinatra proxy (/oc/*); this class is for the Ruby side: health, session list
# for the hammer tasks, and the proxy helper.

require 'net/http'
require 'uri'

module Vibe
  module Opencode
    module_function

    def url path, query = {}
      uri = URI(Vibe.oc_url + path)
      q   = URI.decode_www_form(uri.query.to_s).to_h.merge(query.transform_keys(&:to_s))
      q['directory'] ||= Vibe.root
      uri.query = URI.encode_www_form(q)
      uri
    end

    def get path, query = {}, timeout: 10
      request Net::HTTP::Get.new(url(path, query)), timeout: timeout
    end

    def post path, body = {}, query = {}, timeout: 30
      req = Net::HTTP::Post.new(url(path, query))
      req['content-type'] = 'application/json'
      req.body = JSON.generate(body)
      request req, timeout: timeout
    end

    def request req, timeout: 10
      uri = req.uri
      res = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: timeout) { |http| http.request(req) }
      raise Error, 'opencode %s %s -> %s %s' % [req.method, uri.path, res.code, Vibe.first_line(res.body)] unless res.is_a?(Net::HTTPSuccess)

      ct = res['content-type'].to_s
      ct.include?('json') ? JSON.parse(res.body) : res.body
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout, SocketError => e
      raise Error, 'opencode not reachable at %s (%s)' % [Vibe.oc_url, e.class]
    end

    def up?
      get('/global/health', timeout: 2)
      true
    rescue Error
      false
    end

    def sessions
      list = get('/session')
      list.sort_by { |s| -(s.dig('time', 'updated') || 0) }
    end

    def create_session title = nil
      post '/session', (title ? { title: title } : {})
    end

    def messages id
      get "/session/#{id}/message"
    end

    def prompt id, text
      post "/session/#{id}/prompt_async", { parts: [{ type: 'text', text: text }] }
    end

    def abort id
      post "/session/#{id}/abort"
    end

    def revert id, message_id
      post "/session/#{id}/revert", { messageID: message_id }
    end

    def unrevert id
      post "/session/#{id}/unrevert"
    end

    def session_status
      get '/session/status'
    end

    def vcs_status
      get '/vcs/status'
    end

    # configured model per the running server (what the agent will actually use)
    def providers
      get '/config/providers'
    end
  end
end
