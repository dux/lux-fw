class {{klasses}}Api < ModelApi
  documented

  generate :show
  generate :create
  generate :update
  generate :destroy

  member do
    # define :add_part do
    #   desc '...'
    #   params do
    #   end
    #   proc do
    #   end
    # end
  end
end
