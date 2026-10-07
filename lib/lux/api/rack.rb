# Rack entry for Lux::Api: `map 'api', ApplicationApi` (or `run ApplicationApi`)
# calls `.call env`, auto_mount parses the URL or JSON-RPC body and hands the
# class/action/params to `render` (base_class.rb).

module Lux
  class Api
    @@after_auto_mount = nil

    class << self
      # perform auto_mount from a rack call
      def call env = nil
        return render unless env

        request = Rack::Request.new env

        api_host = Struct.new(:request, :response).new(
          request,
          Struct.new(:header, :status).new({}, 200)
        )

        data = auto_mount api_host: api_host, development: ENV['LUX_ENV'] == 'development'

        # 302 redirect sentinel: auto_mount returned { _redirect: '/path' }
        if data.is_hash? && data[:_redirect]
          return [302, { 'Location' => data[:_redirect], 'Content-Type' => 'text/html' }, []]
        end

        if data.is_hash?
          [
            data[:status] || 200,
            { 'Content-Type' => 'application/json', 'Cache-Control' => 'private, max-age=0' },
            [data.to_json]
          ]
        else
          data = data.to_s
          # merge any headers the action set on api_host.response (Content-Type,
          # Content-Disposition, ETag, Last-Modified, etc.) with sensible defaults
          headers = { 'Cache-Control' => 'private, max-age=0' }
          headers.merge!(api_host.response.header || {})
          headers['Content-Type'] ||= 'text/html'
          # the action can also set status (e.g. send_file emits 304 on If-None-Match)
          status = api_host.response.status || 200
          # 304 / 204 must NOT have a body per HTTP spec
          body = [204, 304].include?(status) ? [] : [data]
          [status, headers, body]
        end
      rescue => error
        # last-resort guard: request parsing (JSON.parse / multipart) and
        # response serialization run outside the per-action rescue_from. Funnel
        # anything that escapes into the same JSON + logged error shape, so an
        # API request never returns a raw 500 or non-JSON body.
        Lux.error.log error unless error.is_a?(Lux::Api::Error)
        body = Response.auto_format error
        [body[:status] || 500, { 'Content-Type' => 'application/json' }, [body.to_json]]
      end

      # ApplicationApi.auto_mount request: request, response: response, mount_on: '/api', development: true
      # auto mount to a root
      # * display doc in a root
      # * call methods if possible /api/v1.comapny/1/show
      def auto_mount api_host:, mount_on: nil, bearer: nil, development: false
        request  = api_host.request
        response = api_host.response

        # Resolution order:
        # 1. explicit `mount_on:` kwarg
        # 2. Rack SCRIPT_NAME (set by lux.response.rack mount_at:) - per-mount override
        # 3. this class's declared mount_on (walks ancestors, default '/api')
        script_name = request.env['SCRIPT_NAME'].to_s if request.respond_to?(:env)
        mount_on ||= (script_name && !script_name.empty? ? script_name : self.mount_on)
        mount_on   = [request.base_url, mount_on].join('') unless mount_on.to_s.include?('//')

        # GET /<mount> serves the human guide (HTML for browsers, markdown
        # otherwise). The raw source brother lives at /<mount>/sys/md.
        # request.path carries SCRIPT_NAME (the mount_at prefix); a rack mount
        # may leave PATH_INFO as '' or '/', so compare with trailing / ignored.
        mount_path = mount_on.to_s.sub(/\A#{Regexp.escape(request.base_url)}/, '')
        mount_path = '/' if mount_path.empty?
        root_hit   = request.path.chomp('/') == mount_path.chomp('/')

        # GET /<mount>/sys/web/<asset> serves the explorer's files by path, so a
        # component URL ends in .fez and fez can name it from the path
        # (Fez.nameFromPath). The ?file= form still works.
        web_asset = "#{mount_path.chomp('/')}/sys/web/"

        if request.request_method == 'GET' && root_hit
          render 'guide', api_host: api_host, development: development, bearer: bearer, class: 'sys'
        elsif request.request_method == 'GET' && request.path.start_with?(web_asset)
          file = request.path[web_asset.length..]
          render 'web', api_host: api_host, development: development, bearer: bearer, class: 'sys', params: { file: file }
        else
          response.header['Content-Type'] = 'application/json' if response

          # Lux::Current already parsed the query string and the form or JSON
          # body; a standalone mount (no Lux app around it) builds its own
          current = request.env['lux.current'] || Lux::Current.new(request.env)
          raise current.malformed_request if current.malformed_request
          params  = current.params

          # class: klass, params: params, bearer: bearer, request: request, response: response, development: development
          opts = {}
          opts[:api_host]    = api_host
          opts[:development] = development
          opts[:bearer]      = bearer

          # A JSON request body is either:
          # (a) a JSON-RPC envelope { class, action, ref, token, params } - has
          #     'class' or 'action' at the top, in which case the URL is ignored.
          #     For member actions provide `ref` (or `id` as alias) with the
          #     resource id; action stays a plain string.
          # (b) a plain params object - use URL path for class+action, body for
          #     params. This matches what fetch(path, { body: JSON.stringify(...) })
          #     looks like in the wild.
          is_rpc_envelope = current.json_request? && (params['class'] || params['action'])

          action =
          if is_rpc_envelope
            opts[:params] = params['params'] || {}
            opts[:bearer] ||= params['token'] if params['token']
            opts[:class]  = params['class']

            # resource ref (member actions); 'ref' is canonical, 'id' is alias
            ref = params['ref']
            ref = params['id'] if ref.nil?
            opts[:id] = ref unless ref.nil?

            params['action']
          else
            opts[:params] = params
            opts[:bearer] ||= params['api_token']

            mount_on = mount_on+'/' unless mount_on.end_with?('/')
            path     = request.url.split(mount_on, 2).last.split('?').first.to_s
            parts    = path.split('/')

            # Format-suffix sugar: the last path segment may carry a recognized
            # file extension (.md / .json / .txt) so URLs look like real files
            # (e.g. /api/sys/AGENTS.md). The extension is stripped and the
            # segment is lower-cased before dispatch, so the action stays a
            # plain Ruby method name (`agents`).
            if parts.last && parts.last =~ /\A([A-Za-z_][A-Za-z0-9_]*)\.(md|json|txt)\z/
              parts[-1] = $1.downcase
            end

            @@after_auto_mount.call parts, opts if @@after_auto_mount

            opts[:class] = parts.shift
            # bare /<mount>/sys -> text index of the reserved system endpoints
            parts = ['index'] if parts.empty? && opts[:class] == 'sys'
            parts
          end

          bearer_token = extract_bearer_token(request.env['HTTP_AUTHORIZATION'])
          opts[:bearer] ||= bearer_token if bearer_token

          api_response = render action, **opts

          if api_response.is_hash?
            response.status = api_response[:status] if response
            api_response.to_h
          else
            api_response
          end
        end
      end

      def after_auto_mount &blok
        @@after_auto_mount = blok
      end

      private

      # extract bearer token from Authorization header
      def extract_bearer_token auth_header
        return nil unless auth_header

        auth_header.to_s.split('Bearer ')[1]
      end
    end
  end
end
