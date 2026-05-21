# Action-level params contract for Lux::Controller.
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
#     def create
#       # current.params already coerced + validated, undeclared keys dropped
#     end
#   end
#
# Both `params do` and `opt` defer to Lux::Schema::Define, so the line
# parser is identical to Lux.schema. Allowed keys per action is the union
# of class-level and method-level rules; method wins on collision.
#
# When no rules are declared for an action, params pass through untouched
# (current behavior). When any rules exist, strict mode applies: undeclared
# keys are dropped, required keys must be present, types are coerced.

module Lux
  class Controller
    module ParamsDsl
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

        # method_added snapshots pending opts onto the action so they survive
        # subsequent def lines without bleeding across methods.
        def method_added name
          super
          if @_pending_opts && @_pending_opts.any?
            @_action_opts ||= {}
            @_action_opts[name] = @_pending_opts
            @_pending_opts = nil
          end
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
