module Lux
  module Favicon
    extend self

    # Renders the <link> tags for a single SVG favicon, including the
    # apple-touch-icon hint for iOS. Modern browsers prefer the SVG;
    # iOS Safari 16.4+ honours SVG for apple-touch-icon and older
    # versions silently fall back to no icon.
    #
    # Lux::Favicon.head                       # => default '/favicon.svg'
    # Lux::Favicon.head '/static/icon.svg'
    def head src = '/favicon.svg'
      [
        %[<link rel="icon" type="image/svg+xml" href="#{src}" />],
        %[<link rel="apple-touch-icon" href="#{src}" />],
      ].join "\n"
    end
  end
end
