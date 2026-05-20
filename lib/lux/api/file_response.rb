# File / data response helper, modeled on Lux::Response::File.
#
# Used by Lux::Api#send_file and #send_data. Sets all the
# expected headers (Content-Type, Content-Disposition, Content-Length,
# Last-Modified, ETag) and short-circuits to 304 when the client sent a
# matching If-None-Match.

require 'pathname'
require 'digest/sha1'
require 'rack/mime'
require 'time'

module Lux
  class Api
    class FileResponse
      OPTS = Struct.new(:name, :file, :content_type, :inline, :download, :disposition, :content, :ext, :path)

      # @param api  Lux::Api#@api struct
      # @param opts Hash:
      #   :file         - filesystem path (String or Pathname)
      #   :content      - raw bytes; mutually exclusive with :file
      #   :name         - download filename (default: basename of file)
      #   :content_type - MIME type override (defaults to mime by extension)
      #
      #   Disposition control (browser behavior). Pick ONE; precedence
      #   top-to-bottom:
      #   :download     - true  => force download (default)
      #                   false => render inline in browser
      #   :inline       - true  => render inline (legacy alias for download:false)
      #   :disposition  - 'attachment' (force download) or 'inline' (view)
      def initialize api, opts = {}
        @api = api
        @opt = OPTS.new

        opts.each { |k, v| @opt[k] = v }

        # Disposition resolution:
        #   explicit :disposition wins; otherwise derive from :download / :inline.
        #   Default is 'attachment' (browser saves the file).
        @opt.disposition ||=
          if @opt.download == false || @opt.inline == true
            'inline'
          else
            'attachment'
          end

        if @opt.file
          @opt.file = Pathname.new(@opt.file) unless @opt.file.is_a?(Pathname)
          @opt.path = @opt.file.to_s
          @opt.ext  = @opt.path.include?('.') ? @opt.path.split('.').last.downcase.to_sym : nil
          @opt.name ||= @opt.file.basename.to_s
        end
      end

      def send
        content = resolve_content

        headers['Content-Type'] = @opt.content_type ||
          ::Rack::Mime.mime_type(".#{@opt.ext}", 'application/octet-stream')

        if @opt.name
          headers['Content-Disposition'] = '%s; filename="%s"' % [@opt.disposition, @opt.name]
        end

        headers['Content-Length'] = content.bytesize.to_s
        headers['Last-Modified']  = @opt.file.mtime.httpdate if @opt.file

        etag_value = '"%s"' % Digest::SHA1.hexdigest(content)
        headers['ETag'] = etag_value

        if request_if_none_match == etag_value
          set_status 304
          @api.raw = ''
        else
          set_status 200
          @api.raw = content
        end

        @api.raw
      end

      private

      def resolve_content
        if @opt.content
          @opt.content
        else
          raise Lux::Api::Error, 'send_file: :file or :content required' unless @opt.file
          raise Lux::Api::Error, 'send_file: file not found: %s' % @opt.path unless @opt.file.exist?
          @opt.file.binread
        end
      end

      def headers
        @api.api_host ? @api.api_host.response.header : {}
      end

      def set_status code
        return unless @api.api_host && @api.api_host.response.respond_to?(:status=)
        @api.api_host.response.status = code
      end

      def request_if_none_match
        @api.request && @api.request.env && @api.request.env['HTTP_IF_NONE_MATCH']
      end
    end
  end
end
