module Lux
  class Api
    class Error < StandardError
    end

    class NotFound < Error
    end

    ANNOTATIONS   ||= {}
    RESCUE_FROM   ||= {}
    OPTS          ||= { api: {} }
    PLUGINS       ||= {}
    MODELS        ||= {}
    DOCUMENTED    ||= []
    INSTANCE      ||= Struct.new 'LuxApiOpts',
      :action,
      :bearer,
      :development,
      :id,
      :method_opts,
      :opts,
      :params,
      :raw,
      :api_host,
      :request,
      :response,
      :uid

    attr_reader :api

    def initialize action, params: {}, opts: {}, development: false, id: nil, bearer: nil, api_host: nil, html_safe: true
      @api = INSTANCE.new

      if action.is_a?(Array)
        # unpack id and action is action is given in path form # [123, :show]
        @api.id, @api.action = action[1] ? action : [nil, action[0]]
      else
        @api.action = action
      end

      if html_safe
        params = Lux::Api.make_hash_html_safe params
      end

      @api.bearer        = bearer
      @api.id          ||= id
      @api.action        = @api.action.to_sym
      @api.request       = api_host ? api_host.request : nil
      @api.method_opts   = self.class.opts.dig(@api.id ? :member : :collection, @api.action) || {}
      @api.development   = !!development
      @api.params        = Lux::Hash.new params
      @api.opts          = Lux::Hash.new opts
      @api.api_host      = api_host
      @api.response      = ::Lux::Api::Response.new @api

      # convenience mirrors of @api.id / @api.bearer, available to before-callbacks
      @ref          = @api.id
      @bearer_token = @api.bearer
    end

    def execute_call
      allow_types  = Array(@api.method_opts[:allow] || 'POST')
      request_type = @api.request&.request_method || 'POST'
      effective_allow_types = allow_types.include?('GET') ? [*allow_types, 'OPTIONS'] : allow_types
      is_allowed   = @api.development || ['POST', *effective_allow_types].include?(request_type)

      if is_allowed
        begin
          parse_api_params
          parse_annotations    unless response.error?
          authenticate_request unless response.error?
          resolve_api_body     unless response.error?
        rescue Lux::Api::NotFound => error
          response.error error.message, status: 404
        rescue Lux::Api::Error => error
          # controlled error raised via error "message", ignore
          response.error error.message
        rescue => error
          # any other error -> render its message as json; the class is kept in
          # meta for diagnostics. Class only matters for logging: real server
          # faults are logged, expected client/validation faults are not.
          Lux.error.log error unless Lux::Api::Response.client_error?(error)

          block = RESCUE_FROM[error.class] || RESCUE_FROM[:all]

          if block
            instance_exec error, &block
          else
            response[:error_class] = error.class.name
            response.error error.message, status: 500
          end
        end

        # we execute generic after block in case of error or no
        execute_callback :after_all
      else
        response.error '%s request is not allowed' % request_type
      end

      @api.raw || response.render
    end

    def to_json
      execute_call.to_json
    end

    def to_h
      execute_call
    end

    private

    def parse_api_params
      params = @api.method_opts[:params]
      schema = @api.method_opts[:_schema]

      if params && schema
        # add validation errors
        schema.validate @api.params do |name, error|
          response.error_detail name, error
        end
      end
    end

    def resolve_api_body &block
      type = @ref ? :member : :collection

      unless self.class.opts.dig(type, @api.action)
        raise Lux::Api::NotFound, "Api method #{type}:#{@api.action} not found"
      end

      method_name = @ref ? "#{@api.action}_ref" : @api.action.to_s

      # belt-and-braces: never dispatch to a method that became private/protected
      # after registration (e.g. via `private :name` flip post-def)
      if self.class.private_method_defined?(method_name) || self.class.protected_method_defined?(method_name)
        raise Lux::Api::NotFound, "Api method #{type}:#{@api.action} not found"
      end

      # execute before "in the wild"
      # model @api.object should be set here
      execute_callback :before_all

      instance_exec &block if block

      execute_callback 'before_%s' % type

      data = send method_name
      response.data data unless response.data?

      # after blocks
      execute_callback 'after_%s' % type
    end

    def parse_annotations
      for key, opts in (@api.method_opts[:annotations] || {})
        instance_exec *opts, &ANNOTATIONS[key]
      end
    end

    # Run the class-level `auth` hook (if declared) unless the endpoint opted
    # out with `unsafe`. The hook gets the bearer token and is expected to
    # reject by setting response.error / raising; on rejection resolve_api_body
    # is skipped. No hook declared -> behavior is unchanged (endpoint stays open).
    def authenticate_request
      return if @api.method_opts[:unsafe]

      block = self.class.opts.dig(:opts, :auth)
      return unless block

      # the hook's return value is the current user, exposed via #user
      @current_user = instance_exec @api.bearer, &block

      # dev aid: make the bearer/unsafe contract obvious when the hook rejects,
      # so a 401 during local work explains itself instead of looking like a bug.
      if @api.development && response.error?
        response.message 'Auth: pass "Authorization: Bearer <token>", or mark this endpoint `unsafe` for anonymous access.'
      end
    end

    def execute_callback name
      # before-callbacks yield the endpoint's method_opts (so a hook can check
      # :unsafe / :allow / custom flags - response.data is still empty here);
      # after-callbacks yield response.data, the value the action produced.
      arg = name.to_s.start_with?('before') ? @api.method_opts : response.data

      self.class.ancestors.reverse.map(&:to_s).each do |klass|
        if before_list = (OPTS.dig(klass, name.to_sym) || [])
          for before in before_list
            instance_exec arg, &before
          end
        end
      end
    end

    def response content_type=nil
      if block_given?
        @api.raw = yield

        api_host do
          response.header['Content-Type'] = content_type || (@api.raw[0] == '{' ? 'application/json' : 'text/plain')
        end
      elsif content_type
        # content_type without a block is almost always a mistake - the arg only
        # labels a raw body. The old behavior silently shipped the string AS the
        # body (response('text/csv') -> body "text/csv"), which hid bugs. Fail
        # loudly and point at the block form instead.
        raise ArgumentError.new('response(content_type) needs a block: response(%p) { body }' % content_type)
      else
        @api.response
      end
    end

    # Send a file from disk to the client. Mirrors Rails / lux-fw API.
    #
    # Default behavior is to FORCE a download (Content-Disposition: attachment),
    # which is the right choice 95% of the time. Pass `download: false` for
    # the few cases where you want the browser to render it inline (PDFs,
    # images, plain text previews).
    #
    #   send_file '/path/to/invoice.pdf'                               # downloads
    #   send_file path, name: 'Invoice-2026.pdf'                       # downloads as "Invoice-2026.pdf"
    #   send_file path, download: false                                # opens in browser
    #   send_file path, download: false, content_type: 'image/png'     # inline image
    #
    # Other supported keys: :content_type, :disposition ('attachment' | 'inline'),
    # :inline (legacy alias for download:false). Sets ETag + Last-Modified
    # automatically and answers 304 to matching If-None-Match requests.
    def send_file path, opts = {}
      Lux::Api::FileResponse.new(@api, opts.merge(file: path)).send
    end

    # Send raw bytes / string (no disk file). Same options as send_file
    # minus :file. Default is to force download.
    #
    #   send_data csv_string, name: 'report.csv', content_type: 'text/csv'
    #   send_data html, name: 'preview.html', content_type: 'text/html', download: false
    def send_data content, opts = {}
      Lux::Api::FileResponse.new(@api, opts.merge(content: content)).send
    end

    def params
      @api.params
    end

    # current user: whatever the class `auth` hook returned. nil when the
    # endpoint is `unsafe` (hook skipped) or no auth hook is declared.
    def user
      @current_user
    end

    # inline error raise
    def error text, args={}
      if @api.development && !Lux.env.test?
        puts 'Lux::Api Error: %s (%s)' % [text, caller[0]]
      end

      if err = RESCUE_FROM[text]
        if err.is_a?(Proc)
          err.call
          return
        else
          response.error err, args
        end
      else
        response.error text, args
      end

      raise Lux::Api::Error, text
    end

    def message data
      response.message data
    end

    # Compatibility shim. Plain `super` now works inside `def`-defined API
    # methods. Inside a `define :foo do; proc { ... }; end` body, `super` and
    # `caller_locations` resolve to the Proc's lexical scope (typically
    # `<class:Foo>`), so we fall back to `@api.action`. Pass `name` explicitly
    # to override the auto-detection.
    def super! name = nil
      if name.nil?
        loc   = caller_locations(1, 1).first
        label = (loc.base_label || loc.label).to_s
        label = label.sub(/^block in /, '')
        # label like '<class:Foo>' / '<top (required)>' means we're inside a
        # Proc body - use the active action instead
        name = label.start_with?('<') ? @api.action.to_s : label.sub(/_ref$/, '')
      end

      method_name = @ref ? "#{name}_ref" : name.to_s
      self.class.superclass.instance_method(method_name).bind(self).call
    end

    # execute actions on api host
    def api_host &block
      if block_given? && @api.api_host
        @api.api_host.instance_exec self, &block
      end

      @api.api_host
    end

  end
end
