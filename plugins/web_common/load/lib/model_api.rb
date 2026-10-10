# Base class for all model CRUD APIs. Provides auto-generated create/show/update/destroy/undelete
# actions via `generate` DSL. Handles object loading from URL path, parameter assignment,
# array/jsonb field toggling, soft delete (is_deleted), and validation error reporting.
# Each model-specific API (e.g. InvoiceApi) inherits from this.

class ModelApi < ApplicationApi

  # Model this API serves. Convention is <Plural>Api -> singular model
  # (UsersApi -> User), but irregular plurals (SickLeavesApi -> SickLeave, not
  # SickLeaf) break naive singularize, so an API may declare `model_class SickLeave`.
  def self.model_class klass = nil
    @model_class = klass if klass
    @model_class ||= to_s.sub(/Api$/, '').singularize.constantize
  end

  # Fields a client may write (generated_create/update assign only these, see
  # object_params) and the schema the API docs list. A model setter that is not
  # a column is declared in the model schema with `virtual: true`.
  def self.api_schema
    model_class.api_schema
  end

  # schemas: key in /sys/schema (see Lux::Api::Introspect)
  def self.api_schema_ref
    model_class.to_s.underscore
  end

  def self.generate name, desc: nil, detail: nil
    # an action the API defines itself wins (member actions live as <name>_ref)
    target = name == :create ? name : :"#{name}_ref"
    return if method_defined?(target) || private_method_defined?(target)

    object_name = to_s.sub(/Api$/, '').tableize.singularize.humanize.downcase
    desc ||= '%s %s' % [name.to_s.capitalize, object_name]

    body = proc do
      self.desc   desc   if desc
      self.detail detail if detail
      # doc generators (postman, openapi, web) list the writable fields
      pending_opts[:params] = api_schema.to_h if %i[create update].include?(name)
      proc { send('generated_%s' % name) }
    end

    name == :create ? define(name, &body) : define_ref(name, &body)
  end

  # { 'user' => { path: '/api/users', member: [...], collection: [...] } } for
  # every model API. Generated into app/assets/lux_models.tmp.js, where
  # dollar_api.js turns it into app.m.user(ref).update(...). Undocumented
  # actions stay off the client index, as they stay off the API schema.
  def self.client_index apis = descendants
    served = {}

    apis.sort_by(&:to_s).each_with_object({}) do |klass, out|
      model = begin
        klass.model_class
      rescue NameError
        next
      end

      key = model.to_s.underscore.tr('/', '_')
      raise ArgumentError, "#{served[key]} and #{klass} both serve #{model}" if served[key]
      served[key] = klass

      actions = -> type {
        (klass.opts[type] || {}).reject { |_, o| o&.dig(:annotations)&.key?(:undocumented) }.keys.map(&:to_s).sort
      }

      out[key] = { path: "#{klass.mount_on}/#{klass.api_path}", member: actions[:member], collection: actions[:collection] }
    end
  end

  before do
    # load generic object based on class name (or declared model_class)
    base = self.class.model_class

    if @api.id
      unless @object = base[@api.id]
        error 'Object %s[%s] is not found' % [base, @api.id]
      end
    else
      @object = base.new
    end

    instance_variable_set '@%s' % base.to_s.underscore, @object
  end

  after do
    if @object.try(:id)
      response.meta :path, @object.path
      response.meta :ref, @object.ref
      response.meta :collection, @object.class.name.tableize
      response.meta :class, @object.class.name.tableize.singularize
    end
  end

  ###

  # toggles value in postgre array field
  def toggle_value field, value, object = nil
    object ||= @object
    object[field] ||= []

    if object[field].include?(value)
      object[field] -= [value]
      object.save
      false
    else
      object[field] += [value]
      object.save
      true
    end
  end

  def report_errros_if_any
    return if @object.errors.count == 0

    for k, v in @object.errors
      desc = v.join(', ')

      response.error_detail k, desc
    end
  end

  # Params a client may never set: the audit quartet is framework-owned and
  # filled by the before_save filters. Removed at every depth so a nested json
  # payload cannot smuggle one in.
  PROTECTED_PARAMS ||= Sequel::Plugins::LuxSchema::AUDIT_COLUMNS

  # Assignable params: only fields of the model's api_schema (`toggle__<field>`
  # counts as <field>). Anything else - is_admin=, ref=, a setter the schema
  # does not declare - is dropped, so the policy never sees a forged value.
  def object_params
    base = params[@object.class.to_s.underscore]
    base = base.respond_to?(:values) ? base : params
    allowed = self.class.api_schema.rules.keys.map(&:to_s)

    base.deep_destroy(*PROTECTED_PARAMS).to_h.select do |key, _|
      ok = allowed.include?(key.to_s.delete_prefix('toggle__'))
      Lux.log { 'ModelApi: unpermitted param "%s" for %s' % [key, @object.class] } unless ok
      ok
    end
  end

  def display_name
    klass = @object.class

    if klass.respond_to?(:display_name)
      klass.display_name
    else
      klass.to_s.humanize
    end
  end

  def generated_show
    params[:full] = true if params[:full].nil?

    @object
      .can
      .read!
      .export params
  end

  ###

  def generated_create
    for k, v in object_params
      v = nil if v.blank?
      @object.send("#{k}=", v) if @object.respond_to?("#{k}=")
    end

    @object.can.create!

    @object.save if @object.valid?

    return if report_errros_if_any

    if @object.id
      message '%s created' % display_name
    else
      error 'object not created, error unknown'
    end

    @object.export
  end

  def generated_update
    error "Object not found" unless @object

    # Policy runs on the stored record first, so a caller cannot write the
    # fields the policy reads (owner refs) and then pass on their new values.
    # The check after assignment still guards the state being written.
    @object.can.update!

    # toggle array or hash field presence
    # toggle__field__value = 0 | 1
    for key, value in object_params
      key = key.to_s
      value = value.xuniq if value.is_a?(Array)

      db_type = @object.db_schema.dig(key.to_sym, :db_type)
      if key.start_with?('toggle__')
        # toggle__foo = 'bar'
        parts = key.split('toggle__')
        field = parts[1].to_sym
        db_type = @object.db_schema.dig(field, :db_type)
        value = value.to_i if db_type.to_s.include?('int')

        next unless @object.respond_to?("#{field}=")

        if @object[field].class.to_s.include?('Array')
          # array field
          @object[field] ||= []
          if @object[field].include?(value)
            @object[field] -= [value]
          else
            @object[field] += [value]
          end
        else
          # jsonb field, toggle true false
          @object[field] ||= {}
          if @object[field][value]
            @object[field].delete value
          else
            @object[field][value] = true
          end
        end

        next
      end

      value = nil if value.class == String && value.blank?
      m = "#{key}=".to_sym

      if @object.respond_to?(m)
        if db_type.to_s.include?('json')
          data = @object.send(key.to_sym) || {}
          data = DeepMerge.deep_merge!(value, data.to_h.dup, preserve_unmergeables: false)
          @object.send(m, data)
          # Lux.logger(:debug).info [key, value, data].to_json
        else
          @object.send(m, value)
        end
      end
    end

    @object.can.update!

    @object.updated_at = Time.now.utc if @object.respond_to?(:updated_at)
    @object.save if @object.valid?

    report_errros_if_any

    response.message '%s updated' % display_name

    @object.export(full: true)
  end

  # if you put active boolean field to objects, then they will be unactivated on destroy
  def generated_destroy force: false
    @object.can.delete!

    if !force && @object.respond_to?(:is_deleted)
      @object.before_destroy
      @object.update is_deleted: true

      message 'Object deleted (exists in trashcan)'
    else
      @object.destroy
      message '%s deleted' % display_name
    end

    true
  end

  def generated_undelete
    error "Object not found" unless @object
    can? :create, @object

    if @object.respond_to?(:is_deleted)
      @object.update is_deleted: false
    else
      error "No is_deleted field, can't undelete"
    end

    response.message = 'Object raised from the dead.'
  end
end
