# Canonical reference example for the Lux::Api DSL.
# Exercised by spec/tests/kitchen_sink_spec.rb. Every feature lives here once.

# --- module that contributes an action via `included` ----------------------

module KitchenSinkPing
  def self.included base
    base.class_eval do
      def ping
        'pong'
      end
    end
  end
end

# --- plugin defined globally, used by the API class ------------------------

Lux::Api.plugin :kitchen_sink_plugin do
  def plugin_provided
    'from_plugin'
  end
end

# --- base class with rescue_from + annotation + custom param type ---------

class KitchenSinkBaseApi < Lux::Api
  mount_on '/kapi'

  rescue_from :forbidden, 'Forbidden'

  rescue_from ArgumentError do |error|
    response.error 'bad-arg', status: 422
  end

  annotation :admin_only do
    @is_admin_call = true
  end
end

# --- inheritance: a child with class-level docs/icon + every DSL piece ----

class KitchenSinkApi < KitchenSinkBaseApi
  include KitchenSinkPing
  plugin :kitchen_sink_plugin

  documented
  class_desc   'Kitchen sink reference API'
  class_detail 'Exercises every Lux::Api DSL feature in one class.'
  icon         '<path d="M0 0h24v24H0z"/>'

  # ---- root-level callbacks fire for collection AND ref actions ----------
  before do
    @root_before_count = (@root_before_count || 0) + 1
  end

  after do
    response.meta :tag, 'kapi'
  end

  # ---- collection: def with desc/detail/params/allow ---------------------

  desc 'List items'
  detail 'Returns a list (no params required)'
  def list
    [{ id: 1 }, { id: 2 }]
  end

  desc 'Stash item via PUT'
  params do
    name String, required: true
    nick? :label   # Typero built-in (slug-like normalization)
  end
  allow :put
  def stash
    { name: params.name, nick: params.nick }
  end

  # ---- collection: define with annotation + RESTful HTTP method ----------

  admin_only
  define :admin_action do
    proc { { admin: @is_admin_call } }
  end

  define get: :rest_get do
    proc { 'rest_get_ok' }
  end

  define [:get, :put] => :rest_multi do
    proc { 'rest_multi_ok' }
  end

  # ---- collection: unsafe ------------------------------------------------

  unsafe
  def public_action
    @api.method_opts[:unsafe]
  end

  # ---- collection: predicate helper extraction --------------------------
  # `current_user?` is private (helper), used by other actions.

  def expose_user
    # Call the public action's underlying logic directly. After helper
    # extraction this would be `_show_for(user)`; here we just demonstrate
    # plain-Ruby method calls between actions / helpers.
    [@ref, @bearer_token, current_user?]
  end

  private

  def current_user?
    !@bearer_token.nil?
  end

  # also private with a trailing `?` to verify it is NOT exposed
  def secret?
    'hidden'
  end

  public

  # ---- ref scope: before-callback + def + define + private helper -------

  ref do
    before do
      @ref_before_count = (@ref_before_count || 0) + 1
    end

    desc 'Show item by ref'
    def show
      { ref: @ref, root_before: @root_before_count, ref_before: @ref_before_count }
    end

    define :detail_action do
      params do
        verbose? String
      end
      proc do
        format = params.verbose.to_s == 'true' ? :long : :short
        { ref: @ref, format: format }
      end
    end

    def trigger_named_rescue
      error :forbidden
    end

    def trigger_class_rescue
      raise ArgumentError, 'boom'
    end

    private

    def ref_helper
      "helper-for-#{@ref}"
    end
  end
end

# --- inheritance: child overrides + super! / super ------------------------

class KitchenSinkChildApi < KitchenSinkApi
  # plain Ruby super works for collection methods (no rename)
  def list
    super + [{ id: 3 }]
  end

  ref do
    # super! is required inside ref do (UnboundMethod rename breaks plain super)
    def show
      base = super!
      base.merge(extended: true)
    end
  end
end
