# Define-time class DSL for Lux::Api.
# Extended onto Lux::Api (and subclasses) so `define` / `params` / `desc` /
# annotations live next to each other, separate from Rack mount + render.

module Lux
  class Api
    module DefineDsl
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
          @pending_opts ||= {}
          @pending_opts[:annotations] ||= {}
          @pending_opts[:annotations][name] = args
        end
      end

      # Register a collection API endpoint (at class root). For member
      # endpoints use `define_ref`, or `define` inside a `ref do` block. A
      # plain `def` is never an endpoint - only `define`/`define_ref` register.
      #
      # Basic usage:
      #   define :foo do
      #     desc 'Foo'        # optional metadata
      #     proc { ... }
      #   end
      #
      # Prefer `allow :get, :put` (varargs or array) to declare HTTP verbs; the
      # get:/array shorthands below still work but are not the documented path.
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

      # Member (ref) counterpart of `define`. Registers an endpoint under
      # :member without an enclosing `ref do` block - sugar for a single
      # member action. The block has the exact same shape as `define`
      # (desc / detail / params / allow / annotations + a returned Proc).
      #
      #   define_ref :show do
      #     desc 'Show one record'
      #     proc { @record.export }
      #   end
      #
      # Reach for `ref do ... end` directly when several member actions share
      # a `before do` (e.g. loading the record).
      def define_ref name = nil, allow: nil, **http_methods, &block
        ref do
          define name, allow: allow, **http_methods, &block
        end
      end

      # Groups member ("ref") actions. Every method defined inside the block
      # (public AND private) is renamed to `<name>_ref` after the block ends,
      # so collection actions can keep the un-suffixed names. The renamed
      # method is what dispatch invokes when a request carries a resource id.
      #
      # Endpoints inside `ref do` are created with `define` (a plain `def` is
      # only a renamed helper, never an endpoint). For a single member action
      # with no shared `before`, `define_ref` is shorter.
      #
      #   ref do
      #     before do
      #       @user = User.find(@ref)
      #     end
      #
      #     define :show do
      #       proc { @user.export }
      #     end
      #
      #     private
      #
      #     def helper     # becomes :helper_ref (private), not an endpoint
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

        @pending_opts ||= {}
        @pending_opts[:_schema] = Lux.schema(&block)
        @pending_opts[:params]  = @pending_opts[:_schema].to_h
      end

      # Point generators (postman, openapi, web) at a named schema for the
      # published contract. Runtime validation still comes only from `params do`
      # (:params / :_schema) - intentional: the documented schema may list
      # fields the action accepts loosely (or omits from coercion/strip), so we
      # do not validate-or-drop against the full schema_ref. See introspect.rb.
      def schema_ref name
        @pending_opts ||= {}
        @pending_opts[:schema_ref] = name.to_s
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
        @pending_opts ||= {}
        @pending_opts[:desc] = data
      end

      # set class-level description
      def class_desc data
        set :opts, :desc, data
      end

      # api method detailed description
      def detail data
        return if data.to_s == ''

        @pending_opts ||= {}
        @pending_opts[:detail] = data
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
      # if defined, access will be allowed via POST + allowed methods.
      # OPTIONS piggybacks on GET when GET is allowed.
      def allow *types
        types = types.flatten.map do |type|
          type = type.to_s.to_sym

          unless %i(get head options post put patch delete trace).include?(type)
            raise ArgumentError.new('"%s" is not allowed http method type' % type)
          end

          type.to_s.upcase
        end

        @pending_opts ||= {}
        @pending_opts[:allow] = types
      end

      # define response content type (defaults to JSON)
      def content_type name
        if name.is_a?(Symbol)
          name = case name
          when :json
            'application/json'
          when :text
            'text/plain'
          else
            raise ArgumentError.new('content-type "%s" is not recognized')
          end
        end

        @pending_opts ||= {}
        @pending_opts[:content_type] = name
      end

      # mark the next endpoint as unsafe: it skips the class `auth` hook and is
      # callable without a bearer token.
      def unsafe
        @pending_opts ||= {}
        @pending_opts[:unsafe] = true
      end

      # Class-level authentication hook. The block receives the request bearer
      # token and runs before every endpoint that is NOT marked `unsafe`.
      # Reject by calling `response.error(...)` (or raising) - the action body
      # is then skipped. Usually it also loads the current user.
      #
      #   auth do |bearer|
      #     @user = User.find_by_token(bearer) or response.error('auth required', status: 401)
      #   end
      #
      # One hook per class; subclasses inherit it until they declare their own.
      # Endpoints opt out individually with `unsafe`. Without a hook the
      # framework enforces nothing - endpoints stay open.
      def auth &block
        raise ArgumentError.new('auth requires a block') unless block_given?

        set :opts, :auth, block
      end

      # block execute before any public method or just some member or collection methods
      # the block is yielded the endpoint's method_opts, so a hook can branch on
      # per-action flags: `before do |opts| ... unless opts[:unsafe] end`
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

      # propagate to Lux::Schema
      def model name, &block
        Lux.schema name, &block
      end

      # Register a named schema for params blocks and document it centrally.
      #   schema :foo, some_schema       # explicit name + Lux::Schema
      #   schema :user, User.api_schema  # alias a model api schema
      #   schema User                    # shortcut -> schema :user, User.api_schema
      # Reference later with `schema(:user)` inside params. ref/id is stripped:
      # a referenced object is validated by its content.
      def schema name, schema_obj = nil
        if schema_obj.nil?                       # lux shortcut: schema User
          raise ArgumentError, 'schema(:name, schema) or schema(ModelClass)' unless name.respond_to?(:api_schema)
          schema_obj = name.api_schema
          name       = name.to_s.split('::').last
        end

        unless schema_obj.is_a?(Lux::Schema)
          raise ArgumentError, 'schema must be a Lux::Schema, got %s' % schema_obj.class
        end

        key = name.to_s.underscore
        Lux::Schema::REFS[key] = schema_obj.except(:ref, :id).as(key)
      end

      # `def` inside an API class is always a plain Ruby helper - it is never
      # an endpoint. Endpoints are created exclusively with `define` (root ->
      # collection) and `define_ref` (member). This callback only clears any
      # pending opts (a stray desc/params/annotation before a plain def) so
      # they cannot leak onto the next define.
      def method_added name
        # the define_method coming from define_single_action manages its own
        # opts and registration - leave them untouched (see @in_define_action)
        return if @in_define_action

        @pending_opts = {}
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
        set type, name, @pending_opts || {}
        @pending_opts = {}

        # wire up the method body. define_method fires method_added; the
        # @in_define_action guard skips it so our just-captured opts and this
        # registration are left intact.
        @in_define_action = true
        self.define_method(name, func)
        @in_define_action = false
      end

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
    end
  end
end
