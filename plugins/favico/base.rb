favicon = Lux.root.join('./public/favicon.png')

die './public/favicon.png not found' unless favicon.exist?

Lux.app.routes do
  Lux::Current::StaticFile.deliver(favicon.to_s) if
    ['/favicon.ico', '/apple-touch-icon.png'].include?(request.path.downcase)
end
