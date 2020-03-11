# Maps routes to method missing for cleaner interface
#    routes do |r|
#      map :about => 'root#about'
#      r.about 'root#about'
module Lux
  class Application
    module Routes
      class MagicRoutes

        def initialize app
          @app = app
        end

        def method_missing route, *args, &block
          @app.map [route, *args, block]
        end
      end

    end
  end
end

