# Serves the interactive API explorer at /<mount>/sys/web.
#
# Default response (no ?file=) is index.html. With ?file=<path> any
# whitelisted file under assets/api/web/ can be served. Paths are always
# interpreted relative to that directory - a leading '/' is allowed as
# URL-syntactic sugar (treated as the web root, never the filesystem
# root). All paths are still strictly validated:
#
#   - no '..' segments anywhere in the path
#   - no scheme (e.g. http://)
#   - resolved file must live under assets/api/web/
#   - extension must be in ALLOWED_EXTS
#
# Content-Type is inferred from the extension.

module Lux
  class Api
    module Web
      extend self

      WEB_DIR     ||= File.expand_path('../../../assets/api/web', __dir__)
      WEB_DIR_ABS ||= File.expand_path(WEB_DIR) + '/'

      DEFAULT_FILE ||= 'index.html'

      CONTENT_TYPES ||= {
        '.html' => 'text/html; charset=utf-8',
        '.htm'  => 'text/html; charset=utf-8',
        '.fez'  => 'text/plain; charset=utf-8',
        '.js'   => 'application/javascript; charset=utf-8',
        '.css'  => 'text/css; charset=utf-8',
        '.map'  => 'application/json; charset=utf-8',
        '.svg'  => 'image/svg+xml',
        '.ico'  => 'image/x-icon',
        '.png'  => 'image/png',
        '.jpg'  => 'image/jpeg',
        '.jpeg' => 'image/jpeg',
        '.gif'  => 'image/gif',
        '.webp' => 'image/webp',
        '.txt'  => 'text/plain; charset=utf-8',
        '.json' => 'application/json; charset=utf-8'
      }.freeze

      ALLOWED_EXTS ||= CONTENT_TYPES.keys.freeze

      # Returns { body:, content_type: } for the requested file, or for
      # index.html when file is nil/blank. Raises ArgumentError for any
      # unsafe input.
      def render file: nil
        raw = file.to_s.strip
        raw = DEFAULT_FILE if raw.empty?

        raise ArgumentError, 'absolute or remote URLs not allowed' if raw.include?('://')
        raise ArgumentError, "'..' segments are not allowed"       if raw.split(%r{[/\\]}).include?('..')

        # strip leading '/' - URL sugar meaning "root of lib/lux/api/web/"
        rel = raw.sub(/^\/+/, '')

        ext = File.extname(rel).downcase
        raise ArgumentError, "file extension not allowed: #{ext.inspect}" unless ALLOWED_EXTS.include?(ext)

        path_abs = File.expand_path(File.join(WEB_DIR, rel))
        raise ArgumentError, 'path escapes web root'  unless path_abs.start_with?(WEB_DIR_ABS)
        raise ArgumentError, "file not found: #{rel}" unless File.file?(path_abs)

        {
          body:         File.read(path_abs),
          content_type: CONTENT_TYPES[ext]
        }
      end
    end
  end
end
