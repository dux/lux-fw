module Lux
  # Server-side renderer for pages / templates / cells.
  # See lib/lux/render/ and lib/lux/router/lib/render.rb.
  #
  #   Lux.render.get('/about').body
  #   Lux.render.template(self, './app/views/foo.haml')
  #   Lux.render.cell(:user).card
  def render
    Lux::Router::Render
  end
end
