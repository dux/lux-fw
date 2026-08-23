# The harness web app: one page (chat | preview / files / git / logs), a small
# JSON api over Vibe::Git / Vibe::Restart, and a same-origin proxy to the
# opencode server so the browser needs no CORS and a single port.
#
# Started by `lux docker:vibe:server` (the vibe container's command) - never loaded by
# an app boot, so sinatra/puma stay optional for the plugin.

require 'sinatra/base'
require 'erb'
require 'net/http'
require 'rack/utils'
require_relative '../vibe'

module Vibe
  class Server < Sinatra::Base
    APP_DIR ||= File.join(Vibe.plugin_root, 'app')

    # headers that must not be copied from the upstream response: the proxy
    # re-frames the body, and SSE would stall behind a buffered length
    HOP_HEADERS ||= %w[content-encoding content-length transfer-encoding connection keep-alive].freeze

    set :environment, :production     # no ShowExceptions html, errors are json below
    set :show_exceptions, false
    set :raise_errors, false
    set :dump_errors, false           # Vibe::Error is an answer, not a crash; real ones are logged below
    set :logging, true
    set :static, false
    set :views, APP_DIR
    set :server, :puma
    set :bind, ENV['VIBE_BIND'] || '0.0.0.0'
    set :port, Vibe.port
    set :protection, except: [:json_csrf, :http_origin] # fetch() posts from the same page

    helpers do
      def h text
        Rack::Utils.escape_html(text.to_s)
      end

      def json obj, code = 200
        status code
        content_type 'application/json'
        JSON.generate(obj)
      end

      # body as a hash: json or form encoded
      def payload
        @payload ||= begin
          raw = request.body.read.to_s
          request.body.rewind rescue nil
          if request.media_type.to_s.include?('json') && !raw.empty?
            JSON.parse(raw)
          else
            params.to_h
          end
        rescue JSON::ParserError
          {}
        end
      end

      def arg name
        payload[name.to_s] || params[name.to_s]
      end

      def serve_static path, type
        halt 404, 'not found' unless File.file?(path)
        cache_control :no_cache
        content_type type
        send_file path
      end

      def app_up?
        uri = URI(Vibe.app_health_url)
        Net::HTTP.start(uri.host, uri.port, open_timeout: 1.5, read_timeout: 2) { |h| h.head(uri.path.empty? ? '/' : uri.path) }
        true
      rescue StandardError
        false
      end

      def fez_js
        [
          File.join(Vibe.root, 'node_modules/@dinoreic/fez/dist/fez.js'),
          File.join(Vibe.root, '.gems/fez/dist/fez.js'),
          File.join(Dir.home, 'dev/gems/fez/dist/fez.js'),
        ].find { |f| File.file?(f) }
      end

      def tail_file path, n
        return '' unless File.file?(path)

        size  = File.size(path)
        bytes = [size, 256 * 1024].min
        data  = File.open(path, 'rb') { |f| f.seek(size - bytes); f.read }
        data.force_encoding('UTF-8').scrub.lines.last(n).join
      end
    end

    error Vibe::Error do
      json({ error: env['sinatra.error'].message }, 422)
    end

    error StandardError do
      e = env['sinatra.error']
      warn "[vibe] #{e.class}: #{e.message}\n  #{Array(e.backtrace).first(6).join("\n  ")}"
      json({ error: '%s: %s' % [e.class, e.message] }, 500)
    end

    not_found do
      json({ error: 'not found: %s' % request.path }, 404)
    end

    # --- page + assets ------------------------------------------------------

    get '/' do
      cache_control :no_cache
      erb :'index.html', locals: {
        app_url: Vibe.app_url,
        model:   Vibe.model,
        branch:  Vibe.branch,
        main:    Vibe.main,
        root:    Vibe.root,
        title:   File.basename(Vibe.root),
      }
    end

    get '/fez.js' do
      file = fez_js
      halt 404, 'fez.js not found - install @dinoreic/fez in the app (bun add @dinoreic/fez) or mount .gems/fez' unless file
      serve_static file, 'application/javascript'
    end

    get '/fez/:name' do
      halt 404 unless params[:name] =~ /\A[\w-]+\.fez\z/
      serve_static File.join(APP_DIR, 'fez', params[:name]), 'text/plain; charset=utf-8'
    end

    get '/vendor/:name' do
      halt 404 unless params[:name] =~ /\A[\w.-]+\z/
      type = params[:name].end_with?('.css') ? 'text/css' : 'application/javascript'
      serve_static File.join(APP_DIR, 'vendor', params[:name]), type
    end

    get '/style.css' do
      serve_static File.join(APP_DIR, 'style.css'), 'text/css'
    end

    # --- status -------------------------------------------------------------

    get '/api/health' do
      branch = Git.current_branch rescue nil
      json(
        branch:   branch,
        on_vibe:  branch == Vibe.branch,
        target:   Vibe.branch,
        opencode: Opencode.up?,
        app:      app_up?,
        app_url:  Vibe.app_url,
        model:    Vibe.model,
        key:      !Vibe.openrouter_key.empty?,
        root:     Vibe.root,
        docker:   Restart.docker_socket?,
        time:     Time.now.to_i
      )
    end

    # --- git ----------------------------------------------------------------

    get '/api/git/status' do
      json Git.status
    end

    get '/api/git/diff' do
      content_type 'text/plain; charset=utf-8'
      Git.diff(params[:path].to_s.empty? ? nil : params[:path])
    end

    get '/api/git/log' do
      json Git.log((params[:n] || 30).to_i)
    end

    post '/api/git/commit_message' do
      json message: CommitMessage.generate
    end

    post '/api/git/commit' do
      message = arg(:message).to_s.strip
      message = CommitMessage.generate if message.empty?
      result  = Git.commit(message)
      result[:pushed] = false
      if arg(:push)
        result.merge!(Git.push)
      end
      json result
    end

    post '/api/git/push' do
      json Git.push
    end

    post '/api/git/pull' do
      json Git.pull
    end

    post '/api/git/merge_main' do
      json Git.merge_main
    end

    post '/api/git/reset' do
      json Git.reset!
    end

    post '/api/git/discard_file' do
      json Git.discard_file(arg(:path))
    end

    # --- restart + logs -----------------------------------------------------

    post '/api/restart' do
      mode = arg(:mode).to_s
      json(mode == 'hard' ? Restart.hard : Restart.soft)
    end

    get '/api/logs' do
      n = [(params[:tail] || 200).to_i, 2000].min
      text = if params[:source] == 'container'
               Restart.container_logs(tail: n)
             else
               tail_file File.join(Vibe.root, 'log/LOG.log'), n
             end
      json text: text, source: params[:source] || 'app'
    end

    # --- opencode proxy -----------------------------------------------------
    #
    # /oc/<path>?<qs> -> <oc_url>/<path>?<qs>&directory=<root>. The SSE stream
    # (/oc/event) is pumped chunk by chunk through a Sinatra stream; everything
    # else is a plain buffered round trip.

    %w[get post put patch delete].each do |verb|
      send(verb, '/oc/*') { proxy_opencode }
    end

    def proxy_opencode
      path  = '/' + params['splat'].first.to_s
      query = Rack::Utils.parse_query(request.query_string)
      query['directory'] ||= Vibe.root
      uri = URI(Vibe.oc_url + path)
      uri.query = Rack::Utils.build_query(query)

      klass = Net::HTTP.const_get(request.request_method.capitalize)
      req   = klass.new(uri)
      req['content-type'] = request.content_type if request.content_type
      req['accept']       = request.get_header('HTTP_ACCEPT') || '*/*'
      if request.body && !%w[GET HEAD].include?(request.request_method)
        req.body = request.body.read
      end

      sse = path == '/event' || req['accept'].to_s.include?('text/event-stream')

      if sse
        req['accept-encoding'] = 'identity'
        content_type 'text/event-stream'
        headers 'Cache-Control' => 'no-cache', 'X-Accel-Buffering' => 'no'
        stream do |out|
          begin
            Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 86_400) do |http|
              http.request(req) do |res|
                res.read_body { |chunk| out << chunk }
              end
            end
          rescue StandardError
            # client went away or upstream died; the browser's EventSource reconnects
          ensure
            out.close rescue nil
          end
        end
      else
        res = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 120) { |http| http.request(req) }
        status res.code.to_i
        res.each_header do |k, v|
          next if HOP_HEADERS.include?(k.downcase)
          headers[k] = v
        end
        body res.body.to_s
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout, SocketError => e
      json({ error: 'opencode not reachable at %s (%s)' % [Vibe.oc_url, e.class] }, 502)
    end

    # config_files '-' keeps puma from picking up the host app's config/puma.rb
    # (it calls lux_boot and sets the app port); an open SSE proxy parks a thread
    # per browser tab, so keep the ceiling roomy
    set :server_settings, { config_files: ['-'], Threads: '2:32' }

    def self.start!
      puts 'vibe harness on http://%s:%s  root=%s  branch=%s  opencode=%s  model=%s' % [bind, port, Vibe.root, Vibe.branch, Vibe.oc_url, Vibe.model]
      run!
    end
  end
end
