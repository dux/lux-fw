class Class

  # OrgsController.source_location -> ../controllers/orgs.rb
  def source_location as_folder=false
    name = instance_methods(false).first || dir('Can not find method')
    name = instance_method(name).source_location.first
    as_folder ? File.dirname(name) : name
  end

end