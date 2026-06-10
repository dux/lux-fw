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

  def self.generate name, desc: nil, detail: nil
    ref_key = model_schema = nil

    # schema-linking is best-effort: a model that can't be resolved by name
    # (irregular plural - declare `model_class`) still gets the action, just
    # without auto schema params, instead of crashing class load.
    begin
      model        = model_class
      ref_key      = model.to_s.underscore
      model_schema = [:create, :update].include?(name) && model.api_schema
    rescue NameError
    end

    object_name = to_s.sub(/Api$/, '').tableize.singularize.humanize.downcase
    desc ||= '%s %s' % [name.to_s.capitalize, object_name]

    # collection action for :create, member action for the rest. The endpoint
    # body just forwards to the matching generated_* helper.
    body = proc do
      self.desc   desc   if desc
      self.detail detail if detail
      params { set "#{ref_key}?", schema(ref_key) } if model_schema
      proc { send('generated_%s' % name) }
    end

    name == :create ? define(name, &body) : define_ref(name, &body)
  end

  before do
    # load generic object based on class name (or declared model_class)
    base = self.class.model_class

    if @api.id
      unless @object = base.find(@api.id)
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

  def same_as_last?
    return unless respond_to?(:creator_ref)

    @last = self.class.xorder('id desc').my.first

    return unless @last

    if respond_to?(:created_at)
      diff = (Time.now.to_i - @last.created_at.to_i)
      return diff < 2
    end

    if respond_to?(:name)
      return true if name == @last.name
    end

    false
  end

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

  def object_params
    base = params[@object.class.to_s.underscore]
    base.respond_to?(:values) ? base : params
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

  # Mass-assignment whitelist from api_schema: only declared schema fields plus
  # explicit domain-model setters (virtual fields like Doc#name=) are assignable;
  # stray params are dropped. Sequel column setters live in an anonymous module and
  # base setters (ref=, current=) live on ApplicationModel, so neither is exposed.
  # Returns nil when the model has no schema, so callers fall back to legacy
  # "assign anything with a setter".
  def assignable_fields
    schema = self.class.model_class.api_schema rescue nil
    return unless schema.respond_to?(:rules) && schema.rules

    fields = schema.rules.keys.map(&:to_sym)
    object_params.each_key do |k|
      sym = k.to_sym
      next if fields.include?(sym)
      owner = @object.respond_to?(:"#{sym}=") ? @object.method(:"#{sym}=").owner : nil
      fields << sym if owner.is_a?(Class) && owner < ApplicationModel
    end
    fields
  end

  def generated_create
    allowed = assignable_fields

    for k, v in object_params
      next if allowed && !allowed.include?(k.to_sym)
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

    allowed = assignable_fields

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
        # toggles allowed only on schema fields
        next if allowed && !allowed.include?(field)
        db_type = @object.db_schema.dig(field, :db_type)

        value = value.to_i if db_type.to_s.include?('int')

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

      # drop anything not declared in api_schema
      next if allowed && !allowed.include?(key.to_sym)

      value = nil if value.blank?
      m = "#{key}=".to_sym

      if @object.respond_to?(m)
        if db_type.to_s.include?('json')
          data = @object.send(key.to_sym) || {}
          data = data.to_h.dup.deep_merge!(value)
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
