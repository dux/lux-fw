class Class

  # Get all class descendants
  # `ApplicationModel.descendants # get all DB models`
  def descendants fast = false
    ObjectSpace.each_object(Class).select do |klass|
      if fast
        klass < self
      else
        klass.ancestors.include?(self)
      end
    end - [self]
  end

  # OrgsController.source_location -> ./apps/controllers/orgs_controller.rb
  def source_location as_folder=false
    root = Lux.root.to_s

    for name in instance_methods(false)
      src = instance_method(name).source_location.first.split(root)[1] || next
      src = '.%s' % src
      return as_folder ? File.dirname(src) : src
    end

    nil
  end

end
