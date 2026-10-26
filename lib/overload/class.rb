class Class

  # Get all class descendants (walks Class#subclasses, no ObjectSpace heap scan)
  # `ApplicationModel.descendants # get all DB models`
  def descendants
    subclasses.flat_map { [_1, *_1.descendants] }
  end

  # OrgsRouter.source_location -> ./app/routers/orgs_router.rb
  def source_location as_folder = false
    file   = name && Object.const_source_location(name)&.first
    file ||= instance_methods(false).filter_map { instance_method(_1).source_location&.first }.first
    return unless file
    src = Lux.root.pretty(file)
    return unless src.start_with?('.')
    as_folder ? File.dirname(src) : src
  end

end
