module Lux
  class Application
    FAVICON_PATH ||= '/favicon.ico'

    # Serve the app icon at /favicon.ico and advertise it in <head> for web
    # (rel=icon) and iOS (rel=apple-touch-icon). `path` is public-dir relative,
    # e.g. favicon '/favicon.svg' -> public/favicon.svg.
    def favicon path
      # Match the bare 'favicon' segment: Nav strips the format suffix, so
      # '/favicon.ico' (and any /favicon.<ext> poll) arrives as path ['favicon'].
      map 'favicon', proc {
        Lux::Response::File.send file: Lux.root.join('public', path.delete_prefix('/')), inline: true
      }

      lux.header.link 'icon',             FAVICON_PATH
      lux.header.link 'apple-touch-icon', FAVICON_PATH
    end
  end
end
