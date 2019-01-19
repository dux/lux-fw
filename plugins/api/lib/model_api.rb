class Sequel::Model
  module InstanceMethods
    def same_as_last_field_value data
      data = data.join('-') if data.is_array?
      data = '' if data.is_hash?
      data
    end

    def same_as_last?
      @last = self.class.xorder('id desc').first
      return unless @last

      return if respond_to?(:name) && name != @last[:name]

      new_o = self.to_h
      new_o.delete :created_at
      new_o.delete :updated_at
      new_o.delete :id

      old_o = new_o.keys.inject({}) do |t, key|
        t[key] = @last.send(key)

        new_o[key] = same_as_last_field_value new_o[key]
        t[key]     = same_as_last_field_value t[key]

        t
      end

      if new_o.to_s.length == old_o.to_s.length
        raise "#{self.class} is the copy of the last one created."
      end
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

  def show
    error "Object not found" unless @object

    can? :read, @object

    attributes
  end

  def create
    @object = @class_name.constantize.new

    for k, v in @params
      v = nil if v.blank?
      @object.send("#{k}=", v) if @object.respond_to?("#{k}=")
    end

    @object.same_as_last? rescue error($!.message)

    can? :create, @object

    @object.save if @object.valid?

    return if report_errros_if_any @object

    if @object.id
      message '%s created' % @class_name.capitalize
    else
      error 'object not created, error unknown'
    end

    add_response_object_path

    attributes
  end

  def update
    error "Object not found" unless @object

    for k,v in @params
      m = "#{k}=".to_sym
      v = nil if v.blank?
      @object.send(m, v) if @object.respond_to?(m)
    end

    can? :update, @object

    @object.updated_at = Time.now.utc if @object.respond_to?(:updated_at)
    @object.save if @object.valid?

    report_errros_if_any @object

    response.message '%s updated' % @class_name

    add_response_object_path

    attributes
  end

  # if you put active boolean field to objects, then they will be unactivated on destroy
  def destroy force: false
    error "Object not found" unless @object
    can? :delete, @object

    if !force && @object.respond_to?(:is_active)
      @object.update is_active: false

      message 'Object deleted (exists in trashcan)'
    elsif !force && @object.respond_to?(:active)
      @object.update active: false

      message 'Object deleted (exists in trashcan)'
    else
      @object.destroy
      message '%s deleted' % @object.class.name
    end

    report_errros_if_any @object

    attributes
  end

  def undelete
    error "Object not found" unless @object
    can? :create, @object

    if @object.respond_to?(:is_active)
      @object.update :is_active=>true
    elsif @object.respond_to?(:active)
      @object.update :active=>true
    else
      error "No is_active, can't undelete"
    end

    response.message = 'Object raised from the dead.'
  end

  private

  def report_errros_if_any obj
    return if obj.errors.count == 0

    for k, v in obj.errors
      desc = v.join(', ')

      response.error k, desc
    end
  end

  def can? action, object=nil
    object ||= @object
    object.can?(action) do |err|
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

end
