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
#   - extension must be in ALLOWED_EXTS (a trailing `.erb` is allowed and
#     stripped before matching - so `foo.html.erb` resolves like `foo.html`
#     and is evaluated through Lux::Api::ErbView)
#
# Content-Type is inferred from the (inner) extension.

module Lux
  class Api
    module Web
      extend self

      WEB_DIR     ||= Lux.fw_root.join('assets/api/web').to_s
      WEB_DIR_ABS ||= WEB_DIR + '/'

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
      #
      # `api` / `mount_on` are forwarded to Lux::Api::ErbView so .erb
      # templates can reach the live request and the introspection schema.
      def render file: nil, api: nil, mount_on: nil
        raw = file.to_s.strip
        raw = DEFAULT_FILE if raw.empty?

        raise ArgumentError, 'absolute or remote URLs not allowed' if raw.include?('://')
        raise ArgumentError, "'..' segments are not allowed"       if raw.split(%r{[/\\]}).include?('..')

        # strip leading '/' - URL sugar meaning "root of assets/api/web/"
        rel = raw.sub(/^\/+/, '')

        # Strip a trailing `.erb` for extension + content-type purposes;
        # the actual on-disk file may have it (foo.html -> foo.html.erb).
        bare = rel.sub(/\.erb\z/, '')
        ext  = File.extname(bare).downcase
        raise ArgumentError, "file extension not allowed: #{ext.inspect}" unless ALLOWED_EXTS.include?(ext)

        path_abs = resolve(rel) || resolve("#{bare}.erb")
        raise ArgumentError, "file not found: #{rel}" unless path_abs

        {
          body:         Lux::Api::ErbView.new(api, mount_on: mount_on).render(path_abs),
          content_type: CONTENT_TYPES[ext]
        }
      end

      private

      def resolve rel
        path_abs = File.expand_path(File.join(WEB_DIR, rel))
        return nil unless path_abs.start_with?(WEB_DIR_ABS)
        return nil unless File.file?(path_abs)
        path_abs
      end
    end
  end
end
