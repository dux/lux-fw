class {{@object.classify}} < ApplicationModel

  attributes do
    set :name, req: '{{@object.classify}} name is required'
  end

end