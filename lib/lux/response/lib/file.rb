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

        def type name
          MIME_TYPES[name.to_sym]
        end

        def send opts
          new(opts).send
        end
      end

      ###

      MIME_TYPES = {
        css:   'text/css',
        scss:  'text/css',
        doc:   'application/msword',
        eot:   'application/vnd.ms-fontobject',
        gif:   'image/gif',
        gz:    'application/x-gzip',
        html:  'text/html',
        ico:   'image/png', # image/x-icon
        jpeg:  'image/jpeg',
        jpg:   'image/jpeg',
        js:    'text/javascript',
        json:  'application/json',
        map:   'application/json',
        mp3:   'application/mp3',
        otf:   'application/font-otf',
        png:   'image/png',
        svg:   'image/svg+xml',
        text:  'text/plain',
        ttf:   'application/font-ttf',
        txt:   'text/plain',
        webp:  'image/webp',
        woff:  'application/x-font-woff',
        woff2: 'application/x-font-woff',
        xml:   'application/xml',
        zip:   'application/x-gzip'
      }

      OPTS = Struct.new 'LuxResponseFileOpts', :name, :file, :content_type, :inline, :disposition, :content, :ext, :path

      ###
      # all params are optional
      # :name          - file name
      # :content_type  - string type
      # :inline        - sets disposition to inline if true
      # :disposition   - inline or attachment
      # :content       - raw file data
      def initialize in_opts = {}
        opts = OPTS.new **in_opts
        opts.disposition ||= opts.inline.class == TrueClass ? 'inline' : 'attachment'
        opts.file = Pathname.new(opts.file) unless opts.file.class == Pathname
        opts.path = opts.file.to_s
        opts.ext  = opts.path.include?('.') ? opts.path.split('.').last.to_sym : nil

        @opts = opts
      end

      define_method(:request)  { Lux.current.request }
      define_method(:response) { Lux.current.response }

      def binary?
        data = @opts.content
        return true if data.include?("\x00")
        # nontext_ratio = data.each_byte.count { |b| b < 9 || (b > 13 && b < 32) || b > 126 }.to_f / data.bytesize
        # nontext_ratio > 0.3
        false
      end

      def is_static_file?
        return false unless @opts.ext
        @opts.file.exist?
      end

      def etag key
        response.headers['etag'] = '"%s"' % key
        response.body('not-modified', status: 304) if request.env['HTTP_IF_NONE_MATCH'] == key
      end

      def get_content_type

      end

      def send
        @opts.name ||= @opts.path.split('/').last
        if @opts.disposition == 'attachment'
          response.headers['content-disposition'] = 'attachment; filename=%s' % @opts.name
        end

        if @opts.content
          etag Crypt.sha1 @opts.content
        else
          raise Lux::Error.not_found('File not found') unless @opts.file.exist?
          file_mtime = @opts.file.mtime.utc.to_s
          @opts.content = @opts.file.read
          response.headers['last-modified'] = file_mtime
          etag Crypt.sha1(@opts.path + (@opts.content || file_mtime.to_s))
        end

        response.headers['access-control-allow-origin'] ||= '*'
        guessed_type = binary? ? 'application/octet-stream' : 'text/plain'
        response.content_type(@opts.content_type || MIME_TYPES[@opts.ext || '_'] || guessed_type)
        response.body @opts.content
      end
    end
  end
end
