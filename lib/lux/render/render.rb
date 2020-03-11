module Lux
  # Lux.app.new(path, full_opts).info
  # Lux.render.post(path, params, rest_of_opts).info
  # Lux.render.get('/search', { q: 'london' }, { session: {user_id: 1} }).info  def render *args
  def render *args
    if args.first
      app.new(*args)
    else
      app::Render
    end
  end
end
