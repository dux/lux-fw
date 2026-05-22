class {{@object.classify}} < ApplicationModel

  attributes do
    string :name, req: '{{@object.classify}} name is required'
  end

end