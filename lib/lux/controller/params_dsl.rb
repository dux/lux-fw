# Action-level params + HTTP-verb contract for Lux::Controller.
#
#   class UsersController < Lux::Controller
#     # class-level: applies to every action in this class
#     params do
#       org_id   :uuid
#       api_key? :string
#     end
#
#     # method-level: applies only to the next def
#     opt :name,  String, max: 30
#     opt :email, type: :email
#     allow :post                       # this action accepts GET + HEAD + POST
#     def create
#       # current.params already coerced + validated, undeclared keys dropped
#     end
#   end
#
# Both `params do` and `opt` defer to Lux::Schema::Define, so the line
# parser is identical to Lux.schema. Allowed keys per action is the union
# of class-level and method-level rules; method wins on collision.
#
# Verb contract: actions are GET (+ implicit HEAD) by default. An `allow`
# line REPLACES the default set with the declared verbs - `allow :post`
# means POST only (no GET). For both, declare both: `allow :get, :post`.
# HEAD is implicit only when GET is in the set. `allow :any` (alias `:all`)
# opts out of the check entirely. A verb not in the set raises 405.

require 'set'

module Lux
  class Controller
    module ParamsDsl
      ALLOWED_HTTP_VERBS ||= %i(get head post put patch delete trace).freeze

      def self.included base
        base.extend ClassMethods
      end

      module ClassMethods
        # Declare class-level params. The block is the same DSL as
        # Lux.schema do ... end.
        def params &block
          raise ArgumentError, 'params requires a block' unless block_given?
          @_params_schema = Lux.schema(&block)
        end

        # Declare a single opt for the next def. `args` is forwarded
        # verbatim to Lux::Schema::Define so positional/kwarg shapes match.
        #
        #   opt :name, String, max: 30   # set :name, type: String, max: 30
        #   opt :name, type: String      # set :name, type: String
        #   opt :name?                   # set :name?, (optional, default :string)
        def opt name, *args, **kwargs
          args = args.dup
          args << kwargs unless kwargs.empty?
          @_pending_opts ||= []
          @_pending_opts << [name, args]
        end

        # Declare an absolute URL that dispatches to the next def. Multiple
        # `route` lines stack - each URL aliases the same action.
        #
        #   route '/users'
        #   def index; end
        #
        #   route '/u/:slug'
        #   route '/users/:slug'
        #   def by_slug; end                # both URLs hit :by_slug
        #
        # Captures land in `nav.params`; a `:ref` capture also binds
        # `nav.ref`. Inside `ref do ... end` the method (and its routes)
        # get the standard `_ref` rename.
        def route path, **opts
          unless path.is_a?(String) && path.start_with?('/')
            raise ArgumentError, 'route path must be a String starting with / (got %s)' % path.inspect
          end
          @_pending_routes ||= []
          @_pending_routes << [path, opts]
        end

        # Declare the exact HTTP verb set the next def accepts. This REPLACES
        # the GET + HEAD default - it is not additive. For dual-verb actions,
        # declare both verbs explicitly. HEAD piggybacks on GET only when GET
        # is in the set.
        #
        #   allow :post                # POST only (no GET)
        #   allow :get, :post          # GET + HEAD + POST
        #   allow :post, :patch        # POST + PATCH only
        #   allow :any                 # accept every verb (alias: :all)
        #
        # Args are flattened, so an accidental array splat still works.
        def allow *verbs
          verbs = verbs.flatten.map { |v| v.to_s.to_sym }
          @_pending_allows ||= []

          if verbs.include?(:any) || verbs.include?(:all)
            @_pending_allows = [:any]
            return
          end

          verbs.each do |v|
            unless ALLOWED_HTTP_VERBS.include?(v)
              raise ArgumentError, '"%s" is not a recognised HTTP verb (got: %s)' % [v, ALLOWED_HTTP_VERBS.join(', ')]
            end
            @_pending_allows << v
          end
        end

        # method_added snapshots pending opts + verb-allows + routes onto the
        # action so they survive subsequent def lines without bleeding across
        # methods. Route declarations are also pushed into the global registry
        # at Lux::Controller.action_routes; the entry's :action key is the
        # current method name (pre-`ref do` rename, if applicable - the rename
        # step in `ref` remaps the entry afterwards).
        def method_added name
          super
          if @_pending_opts && @_pending_opts.any?
            @_action_opts ||= {}
            @_action_opts[name] = @_pending_opts
            @_pending_opts = nil
          end
          if @_pending_allows && @_pending_allows.any?
            @_action_allows ||= {}
            @_action_allows[name] = @_pending_allows
            @_pending_allows = nil
          end
          if @_pending_routes && @_pending_routes.any?
            @_action_routes ||= {}
            @_action_routes[name] = @_pending_routes

            registry = Lux::Controller.action_routes
            # drop any prior registry entries for (this class, this action) so
            # reloads don't pile up. Reload replaces the class object, so we
            # match on class-name string to catch the stale entries too.
            class_name = to_s
            registry.reject! { |e| e[:controller].to_s == class_name && e[:action] == name }
            @_pending_routes.each do |path, opts|
              registry << { controller: self, action: name, path: path, opts: opts }
            end

            @_pending_routes = nil
          end
        end

        # Verbs permitted for `action_name`. Walks the ancestor chain so
        # subclasses inherit parent declarations. The :error action is always
        # permitted on every verb so error rendering never 405s.
        #
        # When the action declares `allow`, the declared set REPLACES the
        # default. HEAD is implicit only when GET is in the declared set.
        # Returns either a `Set` of verb symbols, or the sentinel `:any` for
        # opt-out actions.
        def allowed_verbs_for action_name
          return :any if action_name == :error

          ancestors.each do |a|
            next unless a.is_a?(Class) && a <= Lux::Controller
            store = a.instance_variable_get(:@_action_allows)
            next unless store

            declared = store[action_name]
            next unless declared

            return :any if declared == [:any]
            set = Set.new(declared)
            set << :head if set.include?(:get)
            return set
          end

          Set[:get, :head]
        end

        # Compose class-level + method-level into one Lux::Schema, with
        # method rules winning on collision. Walks the ancestor chain so
        # subclasses inherit parent params/opt declarations.
        def params_schema_for action_name
          class_schema  = nil
          action_pending = nil

          ancestors.each do |a|
            next unless a.is_a?(Class) && a <= Lux::Controller

            if class_schema.nil? && a.instance_variable_defined?(:@_params_schema)
              class_schema = a.instance_variable_get(:@_params_schema)
            end

            if action_pending.nil?
              store = a.instance_variable_get(:@_action_opts)
              action_pending = store[action_name] if store
            end
          end

          return nil unless class_schema || action_pending

          class_rules = class_schema ? class_schema.rules : {}

          if action_pending
            pending = action_pending
            action_schema = Lux.schema do
              pending.each { |n, args| send n, *args }
            end
            combined_rules = class_rules.merge(action_schema.rules)
          else
            combined_rules = class_rules
          end

          Lux::Schema.new(nil, define: Lux::Schema::Define.new(combined_rules))
        end
      end

      # Instance-side. Called from Lux::Controller#action right after the
      # action name is resolved, before any before-filters run. Fails fast
      # with 405 when the request method is not in the per-action allow set.
      def enforce_allowed_verbs!
        verb    = lux.request.request_method.to_s.downcase.to_sym
        allowed = self.class.allowed_verbs_for(@lux.action)
        return if allowed == :any || allowed.include?(verb)

        Lux.error.method_not_allowed Lux.mode.debug?('405 Method Not Allowed') {
          allowed_label = allowed.to_a.map { |v| v.to_s.upcase }.join(', ')
          'Action %s#%s does not allow %s. Allowed: %s. Add `allow :%s` above the def to enable it.' %
            [self.class, @lux.action, verb.upcase, allowed_label, verb]
        }
      end

      # Instance-side. Called from Lux::Controller#action between
      # before_action and the action method. No-op when the action has
      # no declared rules.
      def validate_action_params!
        schema = self.class.params_schema_for(@lux.action)
        return unless schema

        errors = schema.validate(lux.params, strict: true)
        return if errors.empty?

        # JSON contract: halt with 422 + structured body.
        if lux.nav.format.to_s == 'json' || lux.request.content_type.to_s.include?('json')
          lux.response.status 422
          lux.response.content_type = :json
          lux.response.body({ errors: errors }.to_json)
        else
          # HTML: stash errors for the action / form helper to read,
          # fall through so the page can re-render with the original input.
          lux.var[:param_errors] = errors
        end
      end
    end
  end
end
