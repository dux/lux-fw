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
  def toggle!(object, field, value)
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

    @last = @class_name.constantize.my.last rescue @class_name.constantize.last
    if @last && @last[:name].present? && @last[:name] == @params[:name]
      error "#{@class_name} is same as last one created."
    end

    for k,v in @params
      @object.send("#{k}=", v) if @object.respond_to?(k.to_sym)
    end

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
      @object.send("#{k}=", v) if @object.respond_to?(k.to_sym)
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
      response.error desc
    end

    error
  end

  def can? action, object
    object.can?(action) do |err|
      msg  = 'No %s permission for %s' % [action.to_s.sub('?',''), Lux.current.var.user ? Lux.current.var.user.email : :guests]
      msg += ' on %s' % object.class.name if object
      error msg
    end
  end

  def add_response_object_path
    begin
      response.meta :path, @object.path if @object.respond_to?(:path)
    rescue
      nil
    end
  end

  def attributes
    @object.attributes.pluck(:id, :name, :email)
  end

end
