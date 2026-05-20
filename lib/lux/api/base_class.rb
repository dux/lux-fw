module Lux
  class Api
    @@after_auto_mount = nil
    @@opts   = {}

    class << self
      # perform auto_mount from a rack call
      def call env = nil
        return render unless env

        request = Rack::Request.new env

        if request.path == '/favicon.ico'
          [
            200,
            { 'Cache-Control'=>'public; max-age=1000000' },
            [Lux.fw_root.join('assets/api/web/favicon.png').read]
          ]
        else
          api_host = Struct.new(:request, :response).new(
            request,
            Struct.new(:header, :status).new({}, 200)
          )

          data = auto_mount api_host: api_host, development: ENV['RACK_ENV'] == 'development'

          # 302 redirect sentinel: auto_mount returned { _redirect: '/path' }
          if data.is_hash? && data[:_redirect]
            return [302, { 'Location' => data[:_redirect], 'Content-Type' => 'text/html' }, []]
          end

          if data.is_hash?
            [
              data[:status] || 200,
              { 'Content-Type' => 'application/json', 'Cache-Control'=>'private; max-age=0' },
              [data.to_json]
            ]
          else
            data = data.to_s
            # merge any headers the action set on api_host.response (Content-Type,
            # Content-Disposition, ETag, Last-Modified, etc.) with sensible defaults
            headers = { 'Cache-Control' => 'public; max-age=3600' }
            headers.merge!(api_host.response.header || {})
            headers['Content-Type'] ||= 'text/html'
            # the action can also set status (e.g. send_file emits 304 on If-None-Match)
            status = api_host.response.status || 200
            # 304 / 204 must NOT have a body per HTTP spec
            body = [204, 304].include?(status) ? [] : [data]
            [status, headers, body]
          end
        end
      end

      # ApplicationApi.auto_mount request: request, response: response, mount_on: '/api', development: true
      # auto mount to a root
      # * display doc in a root
      # * call methods if possible /api/v1.comapny/1/show
      def auto_mount api_host:, mount_on: nil, bearer: nil, development: false
        request  = api_host.request
        response = api_host.response

        mount_on ||= OPTS[:api][:mount_on] || '/'
        mount_on   = [request.base_url, mount_on].join('') unless mount_on.to_s.include?('//')

        if request.url == mount_on && request.request_method == 'GET'
          # root GET -> redirect to interactive explorer at <mount_on>/sys/web
          prefix = (OPTS.dig(:api, :mount_on) || '/').to_s.chomp('/')
          { _redirect: "#{prefix}/sys/web" }
        else
          response.header['Content-Type'] = 'application/json' if response

          body     = request.body ? request.body.read.to_s : ''
          request.body.rewind if request.body.respond_to?(:rewind)
          body     = body[0] == '{' ? JSON.parse(body) : nil

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
          is_rpc_envelope = body && (body['class'] || body['action'])

          action =
          if is_rpc_envelope
            opts[:params] = body['params'] || {}
            opts[:bearer] ||= body['token'] if body['token']
            opts[:class]  = body['class']

            # resource ref (member actions); 'ref' is canonical, 'id' is alias
            ref = body['ref']
            ref = body['id'] if ref.nil?
            opts[:id] = ref unless ref.nil?

            body['action']
          else
            opts[:params] = body || request.params || {}
            if opts[:params].is_hash?
              opts[:bearer] ||= opts[:params]['api_token'] || opts[:params][:api_token]
            end

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

      # renders api doc or calls api class + action
      def render action = nil, opts = {}
        if action
          unless action[0]
            return error 'Action not defined'
          end
        else
          return RenderProxy.new self
        end

        api_class = if klass = opts.delete(:class)
          klass = klass.split('/') if klass.is_a?(String)
          klass[klass.length-1] += '_api'
          klass = klass.join('/').classify

          # try user-land top-level first, fall back to Lux::Api-internal
          # namespace so reserved APIs like `sys` -> Lux::Api::SysApi work
          # without polluting the global namespace.
          begin
            klass.constantize
          rescue NameError
            begin
              "Lux::Api::#{klass}".constantize
            rescue NameError
              return error 'API class "%s" not found' % klass
            end
          end
        else
          self
        end

        api = api_class.new action, **opts
        api.execute_call
      rescue => error
        error_print error if opts[:development]
        Response.auto_format error
      end

      def render_data action, opts = {}
        response = render action, params: opts
        response && (response[:data] || [])
      end

      # rescue_from CustomError do ...
      # for unhandled
      # rescue_from :all do
      #   api.error 500, 'Error happens'
      # end
      # define handled error code and description
      # error :not_found, 'Document not found'
      # error 404, 'Document not found'
      # in api methods
      # error 404
      # error :not_found
      def rescue_from klass=:all, desc=nil, &block
        RESCUE_FROM[klass] = desc || block
      end

      def after_auto_mount &blok
        @@after_auto_mount = blok
      end

      # show and render single error in class error format
      # usually when API class not found
      def response_error text
        out = Response.new nil
        out.error text
        out.render
      end

      # class errors, raised by params validation
      def error desc
        raise Lux::Api::Error, desc
      end

      def error_print error
        puts
        puts 'Lux::Api error dump'
        puts '---'
        puts '%s: %s' % [error.class, error.message]
        puts '---'
        puts error.backtrace
        puts '---'
      end

      # sets api mount point
      # mount_on '/api'
      def mount_on what
        OPTS[:api][:mount_on] = what
      end

      # if you want to make API DOC public use "documented"
      def documented
        if self == Lux::Api
          DOCUMENTED.sort.uniq.map(&:constantize)
        else
          DOCUMENTED.push to_s unless DOCUMENTED.include?(to_s)
        end
      end

      def api_path
        to_s.underscore.sub(/_api$/, '')
      end

      # define method annotations
      # annotation :unsecure! do
      #   @is_unsecure = true
      # end
      # unsecure!
      # def login
      #   ...
      def annotation name, &block
        ANNOTATIONS[name] = block
        self.define_singleton_method name do |*args|
          @@opts[:annotations] ||= {}
          @@opts[:annotations][name] = args
        end
      end

      # Register an API endpoint. `define` ALWAYS registers (with or without
      # desc). Plain `def` registers only when preceded by a `desc` line,
      # which acts as the opt-in marker. Without `desc`, a `def` is a plain
      # Ruby helper, not an endpoint.
      #
      # Basic usage:
      #   define :foo do
      #     proc { ... }
      #   end
      #
      # Equivalent def form (requires desc as opt-in marker):
      #   desc 'Foo'
      #   def foo
      #     ...
      #   end
      #
      # With HTTP method (RESTful style):
      #   define get: :foo do
      #     proc { ... }
      #   end
      #
      # With allow option:
      #   define :foo, allow: :get do
      #     proc { ... }
      #   end
      #
      # Multiple HTTP methods for same action:
      #   define [:get, :put] => :show do
      #     proc { ... }
      #   end
      #
      #   define :show, allow: [:get, :put] do
      #     proc { ... }
      #   end
      #
      # Hidden from public schemas (still callable):
      #   undocumented
      #   define :internal_thing do
      #     proc { ... }
      #   end
      def define name = nil, allow: nil, **http_methods, &block
        # Handle define get: :foo or define [:get, :put]: :foo syntax
        if name.nil? && http_methods.any?
          http_method_key, action_name = http_methods.first
          # http_method_key can be :get or [:get, :put]
          define_single_action(action_name, http_method_key, &block)
        else
          # Handle define :foo, allow: :get or define :foo, allow: [:get, :put] syntax
          define_single_action(name, allow, &block)
        end
      end

      private

      def define_single_action(name, http_methods = nil, &block)
        allow(*Array(http_methods)) if http_methods
        func = class_exec(&block)
        raise 'Define block has to return a Proc object' unless func.is_a?(Proc)

        # snapshot annotations/desc/etc that were set up immediately before
        # this define call, register the endpoint under :member when inside
        # `ref do`, otherwise under :collection
        type = @method_type == :member ? :member : :collection
        set type, name, @@opts
        @@opts = {}

        # actually wire up the method body
        self.define_method(name, func)
      end

      public

      # Defines a group of member ("ref") actions. Each method defined inside the
      # block (public AND private) is renamed to `<name>_ref` after the block ends,
      # so collection actions can keep the un-suffixed names. The renamed method is
      # what dispatch invokes when a request includes a resource id segment.
      #
      #   ref do
      #     before do
      #       @user = User.find(@ref)
      #     end
      #
      #     def show       # becomes :show_ref
      #       @user.export
      #     end
      #
      #     private
      #
      #     def helper     # becomes :helper_ref (private)
      #     end
      #   end
      def ref &block
        raise ArgumentError, 'ref requires a block' unless block_given?

        before_snapshot = {}
        (instance_methods(false) + private_instance_methods(false) + protected_instance_methods(false)).each do |n|
          before_snapshot[n] = instance_method(n)
        end

        @method_type = :member
        class_exec(&block)
        @method_type = nil

        # epilogue: rename newly defined methods to *_ref. method_added is a
        # no-op for endpoint registration (define handles it), so iterating
        # and define_method'ing here doesn't re-register anything.
        methods_at_end = (instance_methods(false) + private_instance_methods(false) + protected_instance_methods(false))
        methods_at_end.each do |n|
          after_impl  = instance_method(n)
          before_impl = before_snapshot[n]

          next if before_impl && before_impl == after_impl

          was_private   = private_method_defined?(n)
          was_protected = protected_method_defined?(n)

          if before_impl.nil?
            # newly defined inside the block - rename to _ref
            remove_method(n)
          else
            # redefined inside the block - restore outer impl, inner becomes _ref
            remove_method(n)
            define_method(n, before_impl)
          end

          define_method(:"#{n}_ref", after_impl)
          send(:private,   :"#{n}_ref") if was_private
          send(:protected, :"#{n}_ref") if was_protected
        end
      end

      # params do
      #   name? String
      #   email :email
      # end
      def params &block
        raise ArgumentError.new('Block not given for Lux::Api method params') unless block_given?

        @@opts[:_schema] = Lux.schema(&block)
        @@opts[:params]  = @@opts[:_schema].to_h
      end

      # api method icon
      # you can find great icons at https://boxicons.com/ - export to svg
      def icon data
        if @method_type
          raise ArgumentError.new('Icons cant be added on methods')
        else
          set :opts, :icon, data
        end
      end

      # api method description
      def desc data
        @@opts[:desc] = data
      end

      # set class-level description
      def class_desc data
        set :opts, :desc, data
      end

      # api method detailed description
      def detail data
        return if data.to_s == ''

        @@opts[:detail] = data
      end

      # set class-level detailed description
      def class_detail data
        return if data.to_s == ''

        set :opts, :detail, data
      end

      # allow alternative method access
      # allow :get
      # allow :get, :put
      # allow [:get, :put]
      # if defined, access will be allowed via POST + allowed methods
      def allow *types
        types = types.flatten.map do |type|
          type = type.to_s.to_sym

          unless %i(get head post put patch delete trace).include?(type)
            raise ArgumentError.new('"%s" is not allowed http method type' % type)
          end

          type.to_s.upcase
        end

        @@opts[:allow] = types
      end

      # define response content type (defaults to JSON)
      def content_type name
        if name.class == Symbol
          name = case name
          when :json
            'application/json'
          when :text
            'text/plain'
          else
            raise ArgumentError.new('content-type "%s" is not recognized')
          end
        end

        @@opts[:content_type] = name
      end

      # allow methods without @api.bearer token set
      def unsafe
        @@opts[:unsafe] = true
      end

      # block execute before any public method or just some member or collection methods
      def before &block
        set_callback :before, block
      end

      # block execute after any public method or just some member or collection methods
      # used to add meta tags to response
      def after &block
        set_callback :after, block
      end

      # simplified module include, masked as plugin
      # Lux::Api.plugin :foo do ...
      # Lux::Api.plugin :foo
      def plugin name, &block
        if block_given?
          # if block given, define a plugin
          PLUGINS[name] = block
        else
          # without a block execute it
          blk = PLUGINS[name]
          raise ArgumentError.new('Plugin :%s not defined' % name) unless blk
          class_exec &blk
        end
      end

      def get *args
        opts.dig *args
      end

      # dig all options for a current class
      def opts
        out = {}

        # dig down the ancestors tree till Object class
        ancestors.each do |klass|
          break if klass == Object

          # copy all member and collection method options
          keys = (OPTS[klass.to_s] || {}).keys
          keys.each do |type|
            for k, v in (OPTS.dig(klass.to_s, type) || {})
              out[type] ||= {}
              out[type][k] ||= v
            end
          end
        end

        out
      end

      # propagate to Lux::Schema
      def model name, &block
        Lux.schema name, &block
      end

      # `def` inside an API class registers as an endpoint ONLY when preceded
      # by a `desc` line (the opt-in marker). Without `desc`, the method is a
      # plain Ruby helper. `define` always registers, with or without desc.
      # Private/protected methods are never registered as endpoints.
      #
      # Legacy apps that pre-date the desc requirement can opt out per class
      # hierarchy with `def_registration_strict false`, in which case every
      # public def registers (the old Joshua/Lux::Api behavior).
      def method_added name
        unless private_method_defined?(name) || protected_method_defined?(name)
          if @@opts[:desc] || !def_registration_strict?
            type = @method_type == :member ? :member : :collection
            set type, name, @@opts
          end
        end
        @@opts = {}
      end

      # Per-class opt-out from the strict `desc + def` rule. Inherited.
      # Use sparingly - it's intended for legacy code migration.
      def def_registration_strict value = true
        @def_registration_strict = value
      end

      def def_registration_strict?
        return @def_registration_strict if instance_variable_defined?(:@def_registration_strict)
        ancestors.drop(1).each do |k|
          next unless k.is_a?(Class) && k <= Lux::Api
          if k.instance_variable_defined?(:@def_registration_strict)
            return k.instance_variable_get(:@def_registration_strict)
          end
        end
        true
      end

      # Compatibility DSL for older code that used Joshua-style blocks:
      #   collection do; def foo; end; end  -- equivalent to defining at class root
      #   member     do; def foo; end; end  -- equivalent to `ref do ... end`
      def collection &block
        class_exec(&block) if block_given?
      end

      def member &block
        ref(&block)
      end

      def make_hash_html_safe hash
        (hash || {}).each do |k, v|
          if v.is_hash?
            make_hash_html_safe v
          elsif v.class == String
            hash[k] = v.gsub('<', '#LT;')
          end
        end
      end

      private

      def set_callback name, block
        name = [name, @method_type || :all].join('_').to_sym
        set name, []
        OPTS[to_s][name].push block
      end

      # generic opts set
      # set :user_name, :email, :baz
      def set *args
        name, value   = args.pop(2)
        args.unshift to_s
        pointer = OPTS

        for el in args
          pointer[el] ||= {}
          pointer = pointer[el]
        end

        pointer[name] = value
      end

      # extract bearer token from Authorization header
      def extract_bearer_token auth_header
        return nil unless auth_header

        auth_header.to_s.split('Bearer ')[1]
      end
    end

    # Built-in annotation: the action stays callable but is hidden from
    # generated public schemas (Postman / OpenAPI / AGENTS.md). Use for
    # internal-only endpoints you don't want to advertise.
    #
    #   undocumented
    #   define :internal_thing do
    #     proc { ... }
    #   end
    annotation(:undocumented) {} unless ANNOTATIONS.key?(:undocumented)
  end
end
