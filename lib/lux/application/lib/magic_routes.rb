# Maps routes to method missing for cleaner interface
#    routes do |r|
#      map :about => 'root#about'
#      r.about 'root#about'
class Lux::Application::MagicRoutes

  def initialize app
    @app = app
  end

  def method_missing route, *args, &block
    @app.map [route, args.first || block]
  end

end

