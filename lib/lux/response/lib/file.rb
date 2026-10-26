# frozen_string_literal: true

module Lux
  class Response
    class File
      class << self
        def deliver_from_current
          path = Lux.ctx.request.path

          # dev: sass/rollup source maps point the browser at ../../app/assets/*
          if Lux.env.dev? && path.start_with?('/app/assets/')
            root = ::File.expand_path('./app/assets')
            file = ::File.expand_path('.' + path)
            return unless file.start_with?(root + '/')
            source = new(file: file, inline: true)
            return source.deliver if source.is_static_file?
            return
          end

          root = ::File.expand_path('./public')
          path = ::File.expand_path('.' + path, root)
          return unless path.start_with?(root + '/')
          ext = ::File.extname(path).delete_prefix('.')
          return unless ext.length.between?(1, 12)
          rack_file = new file: path, inline: true
          if rack_file.is_static_file?
            # Static assets are safe for shared caches; this also suppresses Set-Cookie.
            response = Lux.ctx.response
            response.cache_public(Lux.config[:static_file_max_age] || 600) unless response.cached?
            response.headers['access-control-allow-origin'] ||= '*'
            rack_file.deliver
          end
        end

        # Look up MIME type by extension. Delegates to Rack::Mime.
        # Lux::Response::File.type('css')   => "text/css"
        # Lux::Response::File.type(:json)   => "application/json"
        # Lux::Response::File.type('xyz')   => nil
        def type name
          ::Rack::Mime.mime_type(".#{name}", nil)
        end

        # MIME type by file name/path extension, octet-stream when unknown.
        def mime_for name
          ::Rack::Mime.mime_type(::File.extname(name.to_s), 'application/octet-stream')
        end

        # Content-Disposition value: ASCII-safe quoted filename plus RFC 5987
        # filename* for the real (UTF-8) name. Shared with Lux::Api::FileResponse.
        def content_disposition kind, name
          ascii = name.to_s.gsub(/[^\x20-\x7e]|["\\]/, '_')
          %[#{kind}; filename="#{ascii}"; filename*=UTF-8''#{ERB::Util.url_encode(name.to_s)}]
        end

        def deliver opts
          new(opts).deliver
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
        @opt.file = Pathname.new(@opt.file.to_s)
        @opt.path = @opt.file.to_s
        src       = @opt.path.empty? ? @opt.name.to_s : @opt.path
        @opt.ext  = ::File.extname(src).delete_prefix('.').presence&.to_sym
      end

      define_method(:request)  { Lux.ctx.request }
      define_method(:response) { Lux.ctx.response }

      def is_static_file? = !!@opt.ext && @opt.file.file?

      def deliver
        named = @opt.name.present?
        @opt.name ||= @opt.path.split('/').last
        if @opt.disposition == 'attachment' || named
          response.headers['content-disposition'] = self.class.content_disposition(@opt.disposition, @opt.name)
        end

        if @opt.content
          response.etag Digest::SHA1.hexdigest(@opt.content)
        else
          raise Lux.error 404, Lux.debug?('404 Not Found') { 'File not found: %s' % @opt.file } unless @opt.file.file?
          @opt.content = @opt.file.binread
          response.etag Digest::SHA1.hexdigest(@opt.path + @opt.content), last_modified: @opt.file.mtime
        end

        response.content_type(@opt.content_type || self.class.mime_for(@opt.path.empty? ? @opt.name : @opt.path))
        response.body @opt.content
      end
    end
  end
end
