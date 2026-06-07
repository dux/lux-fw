# Api response is constructed from this object

module Lux
  class Api
    class Response
      attr_reader :errors

      def self.auto_format error
        Lux.error.log error unless error.is_a?(Lux::Api::Error)

        code     = client_error?(error) ? 400 : 500
        response = new nil
        response.error error.message, code: code, status: code
        response.render
      end

      # Client/request faults (param validation, model validation, malformed
      # JSON body, bad multipart) are expected - they map to 400 and are not
      # logged as server errors. Anything else is an unexpected server error.
      def self.client_error? error
        return true if error.is_a?(Lux::Api::Error)
        name = error.class.name.to_s
        # Lux::Policy::Error = authorization denial; an expected 4xx, not a server 500
        %w[JSON::ParserError Sequel::ValidationFailed Lux::Policy::Error].include?(name) || name.start_with?('Rack::')
      end

      ###

      def initialize api
        @api         = api
        @out         = {}
        @meta        = {}
        @errors      = {}
      end

      def []= key, value
        meta key, value
      end

      # forward header to the host controller's rack response
      def header *args
        rack = @api.api_host&.response
        if args.first
          rack.header[args.first] = args[1] if rack
        else
          rack&.header
        end
      end

      # human readable response message
      def message value, force=false
        if force
          @message = value
        else
          @message ||= value
        end

        nil
      end

      # api meta response, any data is allowed
      def meta key, value = nil
        if value
          @meta[key] = value
        else
          @meta[key]
        end
      end

      # add api response error
      def error messages, args={}
        code   = args.delete(:code)
        status = args.delete(:status)

        raise 'Key %s is not supported' % args.keys.first if args.keys.first

        @status ||= status if status

        @errors[:code]     ||= code if code
        @errors[:messages] ||= []

        unless messages.class == Array
          messages = [messages.to_s]
        end

        for text in messages
          if text.present? && text[0, 2] != '["' && !@errors[:messages].include?(text)
            @errors[:messages].push text
          end
        end
      end

      def error?
        !!(@errors[:messages] || @errors[:details])
      end

      def error_detail name, desc
        error '%s (%s)' % [desc, name]

        @errors[:details]     ||= {}
        @errors[:details][name] = desc
      end

      def data value=:_undefined
        if value == :_undefined
          @data
        else
          @data = value
        end
      end
      alias :data= :data

      def data?
        !@data.nil?
      end

      # render full api response
      def render
        {}.tap do |out|
          if @errors.keys.empty?
            out[:success] = true
          else
            out[:success] = false
            out[:error] = @errors
          end

          out[:meta]    = @meta
          out[:message] = @message if @message
          out[:data]    = @data unless @data.nil?
          out[:status]  = @status || (error? ? 400 : 200)
        end
      end
    end
  end
end
