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
          if rack_file.is_static_file?
            # Static assets are safe for shared caches; this also suppresses Set-Cookie.
            response = Lux.current.response
            response.cache_public(Lux.config[:static_file_max_age] || 600) unless response.cached?
            rack_file.send
          end
        end

        # Look up MIME type by extension. Delegates to Rack::Mime.
        # Lux::Response::File.type('css')   => "text/css"
        # Lux::Response::File.type(:json)   => "application/json"
        # Lux::Response::File.type('xyz')   => nil
        def type name
          ::Rack::Mime.mime_type(".#{name}", nil)
        end

        def send opts
          new(opts).send
        end
      end

      OPTS ||= Struct.new 'LuxResponseFileOpts', :name, :file, :content_type, :inline, :disposition, :content, :ext, :path

      ###
      # all params are optional
      # :name          - file name
      # :content_type  - string type
      # :inline        - sets disposition to inline if true
      # :disposition   - inline or attachment
      # :content       - raw file data
      def initialize in_opts = {}
        @opt = OPTS.new **in_opts
        @opt.disposition ||= @opt.inline.class == TrueClass ? 'inline' : 'attachment'
        @opt.file = Pathname.new(@opt.file) unless @opt.file.class == Pathname
        @opt.path = @opt.file.to_s
        @opt.ext  = @opt.path.include?('.') ? @opt.path.split('.').last.to_sym : nil
      end

      define_method(:request)  { Lux.current.request }
      define_method(:response) { Lux.current.response }

      def is_static_file?
        return false unless @opt.ext
        @opt.file.exist?
      end

      def etag key
        quoted = '"%s"' % key
        response.headers['etag'] = quoted
        if request.env['HTTP_IF_NONE_MATCH'] == quoted
          response.status = 304
          response.body   = ''
        end
      end

      def send
        @opt.name ||= @opt.path.split('/').last
        if @opt.disposition == 'attachment'
          response.headers['content-disposition'] = 'attachment; filename=%s' % @opt.name
        end

        if @opt.content
          etag Lux::Utils::Crypt.sha1 @opt.content
        else
          Lux.error 404, Lux.mode.errors?('404 Not Found') { 'File not found: %s' % @opt.file } unless @opt.file.exist?
          file_mtime = @opt.file.mtime.utc.to_s
          @opt.content = @opt.file.read
          response.headers['last-modified'] = file_mtime
          etag Lux::Utils::Crypt.sha1(@opt.path + (@opt.content || file_mtime.to_s))
        end

        response.headers['access-control-allow-origin'] ||= '*'
        response.content_type(
          @opt.content_type ||
          ::Rack::Mime.mime_type(".#{@opt.ext}", 'application/octet-stream')
        )
        response.body @opt.content
      end
    end
  end
end
