class Class

  # Get all class descendants (walks Class#subclasses, no ObjectSpace heap scan)
  # `ApplicationModel.descendants # get all DB models`
  def descendants
    subclasses.flat_map { [_1, *_1.descendants] }
  end

  # OrgsController.source_location -> ./app/controllers/orgs_controller.rb
  def source_location as_folder=false
    for name in instance_methods(false)
      src = Lux.root.pretty(instance_method(name).source_location.first)
      next unless src.start_with?('.')
      return as_folder ? File.dirname(src) : src
    end

    nil
  end

end
