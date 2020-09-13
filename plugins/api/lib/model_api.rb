class Sequel::Model
  module InstanceMethods
    def same_as_last?
      return unless respond_to?(:created_by)

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
  end
end

###

class ModelApi < ApplicationApi
  class << self
    def toggle_ids name
      self.class_eval %[
        param :#{name}_id, Integer
        def toggle_#{name}
          message toggle!(@object, :#{name}_ids, @_#{name}_id) ? 'added' : 'removed'
        end
      ]
    end
  end

  def object_params
    @params[@object.class.to_s.underscore] || @params
  end

  # toggles value in postgre array field
  def toggle! object, field, value
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

  ###

  def index
    raise 'No index method defiend'
  end

  desc 'Show the object'
  def show
    error "Object not found" unless @object

    can? :read, @object

    attributes
  end

  desc 'Create the object'
  def create
    @object = @class_name.constantize.new

    for k, v in object_params
      v = nil if v.blank?
      @object.send("#{k}=", v) if @object.respond_to?("#{k}=")
    end

    error('Object is same as last or added too soon') if @object.same_as_last?

    can? :create, @object

    @object.save if @object.valid?

    return if report_errros_if_any @object

    if @object.id
      message '%s created' % display_name
    else
      error 'object not created, error unknown'
    end

    add_response_object_path

    attributes
  end

  desc 'Update the object'
  def update
    error "Object not found" unless @object

    # toggle array or hash field presence
    # toggle__field__value = 0 | 1
    for k, v in object_params
      k = k.to_s
      v = v.xuniq if v.is_a?(Array)

      db_type = @object.db_schema.dig(k.to_sym, :db_type)

      if k.starts_with?('toggle__')
        field, value = k.split('__').drop(1)

        value = value.to_i if db_type.include?('int')

        if @object[field.to_sym].class.to_s.include?('Array')
          # array field
          @object.send('%s=' % field, @object.send(field).to_a - [value])
          @object.send('%s=' % field, @object.send(field).to_a + [value]) if v.to_i == 1
        else
          # jsonb field, toggle true false
          @object.send(field)[value] = v.to_i == 1
        end

        next
      end

      v = nil if v.blank?
      m = "#{k}=".to_sym

      if db_type.to_s.include?('json')
        @object[k.to_sym] = @object[k.to_sym].merge(v)
      else
        @object.send(m, v) if @object.respond_to?(m)
      end
    end

    can? :update, @object

    @object.updated_at = Time.now.utc if @object.respond_to?(:updated_at)
    @object.save if @object.valid?

    report_errros_if_any @object

    response.message '%s updated' % display_name

    add_response_object_path

    attributes
  end

  # if you put active boolean field to objects, then they will be unactivated on destroy
  desc 'Destroy the object'
  def destroy force: false
    error "Object not found" unless @object
    can? :delete, @object

    if !force && @object.respond_to?(:is_deleted)
      @object.update is_deleted: true

      message 'Object deleted (exists in trashcan)'
    else
      @object.destroy
      message '%s deleted' % display_name
    end

    report_errros_if_any @object

    attributes
  end

  desc 'Try to undelete the object'
  def undelete
    error "Object not found" unless @object
    can? :create, @object

    if @object.respond_to?(:is_deleted)
      @object.update is_deleted: false
    else
      error "No is_deleted field, can't undelete"
    end

    response.message = 'Object raised from the dead.'
  end

  private

  def report_errros_if_any obj
    return if obj.errors.count == 0

    ap ['MODEL API ERROR, params ->', @params]

    for k, v in obj.errors
      desc = v.join(', ')

      response.error k, desc
    end
  end

  def can? action, object=nil
    object ||= @object
    object.can.send('%s!' % action) do |err|
      msg  = 'No %s permission for %s (%s)' % [action.to_s.sub('?',''), Lux.current.var.user ? Lux.current.var.user.email : :guests, err.split(' - ').first]
      msg += ' on %s' % object.class.name if object
      error msg
    end
  end

  def add_response_object_path
    begin
      if @object.respond_to?(:path)
        response.meta :path, @object.path
        response.meta :string_id, @object.id.string_id
      end
    rescue
      nil
    end
  end

  def attributes
    @object.attributes.pluck(:id, :name, :email)
  end

  def display_name
    klass = @object.class

    if klass.respond_to?(:display_name)
      klass.display_name
    else
      klass.to_s.humanize
    end
  end

end
