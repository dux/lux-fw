module Lux
  # Server-side renderer for pages / controllers / templates / cells.
  # See lib/lux/render/ and lib/lux/application/lib/render.rb.
  #
  #   Lux.render.get('/about').body
  #   Lux.render.controller('users#show') { @user = User.first }.body
  #   Lux.render.template(self, './app/views/foo.haml')
  #   Lux.render.cell(:user).card
  def render
    Lux::Application::Render
  end
end
