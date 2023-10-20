# frozen_string_literal: true

module Lux
  class Response
    class File
      class << self
        def deliver_from_current
          path = './public' + Lux.current.request.path
          ext = path.split('.').last
          return unless ext.length > 1 && ext.length < 5
          rack_file = new file: path, inline: true
          rack_file.send if rack_file.is_static_file?
        end
      end

      ###

      MIMME_TYPES = {
        text:  'text/plain',
        txt:   'text/plain',
        html:  'text/html',
        gif:   'image/gif',
        jpg:   'image/jpeg',
        jpeg:  'image/jpeg',
        png:   'image/png',
        ico:   'image/png', # image/x-icon
        css:   'text/css',
        map:   'application/json',
        js:    'text/javascript',
        json:  'application/json',
        gz:    'application/x-gzip',
        zip:   'application/x-gzip',
        svg:   'image/svg+xml',
        mp3:   'application/mp3',
        woff:  'application/x-font-woff',
        woff2: 'application/x-font-woff',
        ttf:   'application/font-ttf',
        eot:   'application/vnd.ms-fontobject',
        otf:   'application/font-otf',
        doc:   'application/msword'
      }

      ###
      # all parametars are optional
      # :name          - file name
      # :cache         - client cache in seconds
      # :content_type  - string type
      # :inline        - sets disposition to inline if true
      # :disposition   - inline or attachment
      # :content       - raw file data
      def initialize in_opts = {}
        opts = in_opts.to_hwia :name, :file, :cache, :content_type, :inline, :disposition, :content, :ext, :path
        opts.disposition ||= opts.inline.class == TrueClass ? 'inline' : 'attachment'
        opts.cache         = true if opts.cache.nil?

        opts.file = Pathname.new(opts.file) unless opts.file.class == Pathname
        opts.path = opts.file.to_s
        opts.ext  = opts.path.include?('.') ? opts.path.split('.').last.to_sym : nil

        @opts = opts
      end

      define_method(:request)  { Lux.current.request }
      define_method(:response) { Lux.current.response }

      def is_static_file?
        return false unless @opts.ext
        @opts.file.exist?
      end

      def etag key
        response.headers['etag'] = '"%s"' % key
        response.body('not-modified', status: 304) if request.env['HTTP_IF_NONE_MATCH'] == key
      end

      def send
        @opts.name ||= @opts.path.split('/').last
        if @opts.disposition == 'attachment'
          response.headers['content-disposition'] = 'attachment; filename=%s' % @opts.name
        end

        response.content_type(@opts.content_type || MIMME_TYPES[@opts.ext || '_'] || 'application/octet-stream')
        response.headers['access-control-allow-origin'] = '*'
        response.headers['cache-control'] = Lux.env.no_cache? ? 'public' : 'max-age=%d, public' % (@opts.cache ? 31536000 : 0)

        if @opts.content
          etag Crypt.sha1 @opts.content
          response.body @opts.content
        else
          raise Lux::Error.not_found('File not found') unless @opts.file.exist?
          file_mtime = @opts.file.mtime.utc.to_s
          response.headers['last-modified'] = file_mtime
          etag Crypt.sha1(@opts.path + (@opts.content || file_mtime.to_s))
          response.body @opts.file.read
        end
      end
    end
  end
end
