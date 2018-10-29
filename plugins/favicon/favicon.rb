favicon = Lux.root.join('./public/favicon.png')

die './public/favicon.png not found' unless favicon.exist?

favicon = favicon.read

Lux.app.before do
  Lux::Response::File.new('favicon.png', inline: true).send(favicon) if
    ['/favicon.ico', '/apple-touch-icon.png'].include?(request.path.downcase)
end
