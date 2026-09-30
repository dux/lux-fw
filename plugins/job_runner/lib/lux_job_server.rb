# Standalone LuxJob web app: the dashboard and the worker loop in one process,
# gated by AuthCog with an admin-email allowlist.
#
# Started by `lux job_runner:web` (see the plugin Hammerfile); never loaded by an
# app boot, so sinatra/puma stay optional for the plugin. The process is expected
# to be the only runner - LuxJob.run dies loudly if another already holds the
# advisory lock, so don't run `job_runner:start` beside it.
#
# Config (app config.yaml):
#   secret         - required, signs the session cookie
#   admin_emails   - array of emails allowed in; empty fails closed
#   host           - bounds which request hosts a callback hash may be exchanged for
#   authcog_realm  - optional authcog.com subdomain (default 'auth')

require 'securerandom'
require 'digest'
require 'sinatra/base'
require_relative '../../authcog/lib/authcog'

class LuxJob
  class Server < Sinatra::Base
    SESSION_STATE   ||= :lux_job_state
    CHALLENGE_LIMIT ||= 4

    # Fez (pjax + components) is served from the app when installed, otherwise
    # from the published build. LUX_JOB_FEZ overrides either.
    FEZ_ONLINE ||= 'https://dux.github.io/fez/dist/fez.min.js'
    FEZ_LOCAL  ||= [
      'node_modules/fez/dist/fez.min.js',
      'node_modules/@dinoreic/fez/dist/fez.min.js',
      '.libs/fez/dist/fez.min.js'
    ].freeze

    # Reachable without a session so the login/denied pages can still boot Fez.
    PUBLIC_PATHS ||= ['/authcog', '/fez.js'].freeze

    set :port, ENV['PORT'].to_i
    set :bind, ENV['LUX_JOB_BIND'] || '127.0.0.1'
    set :server, :puma
    # config_files '-' keeps puma from picking up the app's config/puma.rb
    # (it calls lux_boot and binds the app port)
    set :server_settings, { config_files: ['-'], Threads: '2:16' }
    set :views, File.expand_path('../web', __dir__)
    set :show_exceptions, false
    set :raise_errors, false
    set :dump_errors, true
    set :logging, true
    set :static, false
    # rack-session's encrypted cookie wants a >= 64-byte key; a sha256 hex
    # digest is exactly that whatever the app configured as `secret`.
    set :session_secret, Digest::SHA256.hexdigest(Lux.config[:secret].to_s)
    # http_origin stays on: it is what stops other sites posting here.
    set :protection, except: [:json_csrf], reaction: :deny
    # No host allow-list: the dashboard is reached on a lvh.me subdomain in dev,
    # which Sinatra's development default would reject.
    set :host_authorization, permitted_hosts: []
    enable :sessions

    helpers do
      def h text
        Rack::Utils.escape_html(text.to_s)
      end

      def json obj, code = 200
        status code
        content_type 'application/json'
        JSON.generate(obj)
      end

      def admin_emails
        Array(Lux.config[:admin_emails]).map { |e| e.to_s.downcase }.reject(&:empty?)
      end

      def signed_in?
        !session[:admin_email].to_s.empty?
      end

      def fez_src
        LuxJob::Server.fez_src
      end

      def registered_jobs
        LuxJob::JOBS.map do |name, opts|
          { name: name, every: opts[:every], timeout: opts[:timeout] || LuxJob::DEFAULT_TIMEOUT,
            db: LuxJob.first(name: name.to_s) }
        end
      end

      # AuthCog endpoint for the host this request arrived on, trusted only
      # inside the configured domain; any other Host header falls back to
      # config.host so a forged header cannot pick the exchange domain.
      def auth_base
        home = Lux::Utils::Url.new(Lux.config.host.to_s)
        here = Lux::Utils::Url.new(request.base_url)
        here = home unless here.domain == home.domain

        Authcog.auth_url(here.host, here.port)
      end

      def here
        Lux::Utils::Url.new(request.base_url)
      end

      def start_login
        state = SecureRandom.urlsafe_base64(24)
        held  = Array(session[SESSION_STATE])
        session[SESSION_STATE] = (held + [state]).last(CHALLENGE_LIMIT)

        redirect "#{auth_base}?state=#{Rack::Utils.escape(state)}"
      end

      # Only a challenge this browser is holding is accepted: a login someone
      # else started cannot be landed in this session.
      def claim_challenge given
        given = given.to_s
        return false if given.empty?

        held = Array(session[SESSION_STATE])
        hit  = held.find { |s| Rack::Utils.secure_compare(s.to_s, given) }
        return false unless hit

        session[SESSION_STATE] = held - [hit]
        true
      end

      def complete_login callback_hash
        data  = Authcog.exchange(callback_hash, host: here.host, port: here.port)
        email = data[:email].to_s
        halt 400, 'AuthCog returned no email' if email.empty?

        Lux.logger(:lux_job).info "job web login - #{email} (#{data[:provider]})"

        unless admin_emails.include?(email.downcase)
          halt 403, erb(:denied, locals: { email: email })
        end

        session[:admin_email] = email
        redirect '/'
      rescue Authcog::Error => e
        halt 400, e.message
      end
    end

    before do
      next if PUBLIC_PATHS.include?(request.path_info)
      redirect '/authcog' unless signed_in?
    end

    # Local Fez build from the app (see FEZ_LOCAL); the layout falls back to
    # FEZ_ONLINE when there is none.
    get '/fez.js' do
      file = LuxJob::Server.fez_file
      halt 404, 'no local fez build - using the online lib' unless file

      cache_control :public, max_age: 3600
      content_type 'application/javascript'
      send_file file
    end

    get '/authcog' do
      if params[:callback]
        callback_hash = params[:callback].to_s
        halt 400, 'Missing callback' unless callback_hash =~ /\A[A-Za-z0-9]{40}\z/
        halt 400, 'Unsolicited login' unless claim_challenge(params[:state])

        complete_login(callback_hash)
      else
        start_login
      end
    end

    get '/logout' do
      session.clear
      redirect '/authcog'
    end

    get '/' do
      erb :index, locals: {
        jobs: registered_jobs,
        recent: LuxJob.tail_log(lines: 100),
        last_id: LuxJob.last_log_id
      }
    end

    get '/jobs/:name' do
      name = params[:name].to_s
      info = LuxJob::JOBS[name.to_sym]
      halt 404, 'Job not found' unless info

      erb :show, locals: {
        name: name,
        info: info,
        db: LuxJob.first(name: name),
        lines: LuxJob.tail_log(name: name, lines: 1000),
        last_id: LuxJob.last_log_id(name: name)
      }
    end

    post '/jobs/:name/trigger' do
      name = params[:name].to_sym
      halt 404, json(error: "Job '#{name}' not defined") unless LuxJob::JOBS[name]

      payload = begin
        JSON.parse(request.body.read)
      rescue JSON::ParserError
        {}
      end
      opts = payload['opts']
      halt 422, json(error: 'opts must be a JSON object') unless opts.nil? || opts.is_a?(::Hash)

      job = LuxJob.add(name, opts || {})
      json ok: true, ref: job.ref, name: name.to_s
    end

    get '/api/poll' do
      json last_id: LuxJob.last_log_id(name: params[:name])
    end

    get '/api/log' do
      lines = LuxJob.tail_log(name: params[:name], lines: (params[:lines] || 100).to_i)
      if params[:format] == 'text'
        content_type 'text/plain; charset=utf-8'
        lines.join("\n")
      else
        json lines: lines
      end
    end

    error 404 do
      json({ error: 'not found', path: request.path_info }, 404)
    end

    error StandardError do
      e = env['sinatra.error']
      warn "[lux_job_web] #{e.class}: #{e.message}\n  #{Array(e.backtrace).first(6).join("\n  ")}"
      json({ error: '%s: %s' % [e.class, e.message] }, 500)
    end

    # Host that actually works for authcog: jobs.lvh.me resolves to 127.0.0.1,
    # so opening it keeps the request on a subdomain of the app's own domain and
    # the callback is accepted. LUX_JOB_URL overrides both host and scheme.
    def self.display_url
      ENV['LUX_JOB_URL'] || "http://jobs.lvh.me:#{port}"
    end

    # First local Fez build installed in the app, or nil.
    def self.fez_file
      FEZ_LOCAL.map { |path| File.expand_path(path) }.find { |file| File.file?(file) }
    end

    # What the layout loads: an explicit override, the app's local build served
    # at /fez.js, or the published build.
    def self.fez_src
      ENV['LUX_JOB_FEZ'] || (fez_file ? '/fez.js' : FEZ_ONLINE)
    end

    def self.start!
      Lux.shell.die 'PORT not set - the web service is opt-in (set PORT or pass -p PORT)' if ENV['PORT'].to_s.empty?
      Lux.shell.die 'Lux.config.secret is required for the LuxJob web app' if Lux.config[:secret].to_s.empty?
      if Array(Lux.config[:admin_emails]).empty?
        Lux.shell.info 'LuxJob web: no admin_emails configured - nobody can sign in'
      end

      LuxJob.init!
      Thread.new { LuxJob.run }.tap { |t| t.name = 'lux_job_runner' }

      # Puma prints its own banner during run!; on_booted is the first point
      # after it (and the only one where the server is actually up), so the
      # URL lands at the end of boot instead of scrolling past it.
      # require 'puma' first: puma/events.rb uses Puma.deprecate_method_change,
      # defined in puma.rb, so events alone blows up on Puma 8.
      require 'puma'
      require 'puma/events'
      events = Puma::Events.new
      # Puma 8 renamed on_booted -> after_booted (on_booted warns); keep both.
      hook = events.respond_to?(:after_booted) ? :after_booted : :on_booted
      events.public_send(hook) { Lux.shell.info "LuxJob web on #{display_url} (#{Lux.env})" }
      set :server_settings, server_settings.merge(events: events)

      run!
    end
  end
end
