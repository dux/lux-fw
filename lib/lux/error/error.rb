# frozen_string_literal: true

# https://en.wikipedia.org/wiki/List_of_HTTP_status_codes

# default error handler for lux
# e = Lux::Error.new 404
# e.code => 404
# e.message => 'Not Found'
#
# e = Lux::Error.not_found('foo')
# e.code => 404
# e.message => foo
module Lux
  class Error < StandardError
    class AutoRaise < Lux::Error
    end

    # https://httpstatuses.com/
    CODE_LIST ||= {
      # 1×× Informational
      100 => { name: 'Continue' },
      101 => { name: 'Switching Protocols' },
      102 => { name: 'Processing' },

      # 2×× Success
      200 => { name: 'OK' },
      201 => { name: 'Created' },
      202 => { name: 'Accepted' },
      203 => { name: 'Non-authoritative Information' },
      204 => { name: 'No Content' },
      205 => { name: 'Reset Content' },
      206 => { name: 'Partial Content' },
      207 => { name: 'Multi-Status' },
      208 => { name: 'Already Reported' },
      226 => { name: 'IM Used' },

      # 3×× Redirection
      300 => { name: 'Multiple Choices' },
      301 => { name: 'Moved Permanently' },
      302 => { name: 'Found' },
      303 => { name: 'See Other' },
      304 => { name: 'Not Modified' },
      305 => { name: 'Use Proxy' },
      307 => { name: 'Temporary Redirect' },
      308 => { name: 'Permanent Redirect' },

      # 4×× Client Error
      400 => { name: 'Bad Request',        code: :bad_request },
      401 => { name: 'Unauthorized',       code: :unauthorized },
      402 => { name: 'Payment Required',   code: :payment_required },
      403 => { name: 'Forbidden',          code: :forbidden },
      404 => { name: 'Document Not Found', code: :not_found },
      405 => { name: 'Method Not Allowed', code: :method_not_allowed },
      406 => { name: 'Not Acceptable',     code: :not_acceptable },
      407 => { name: 'Proxy Authentication Required' },
      408 => { name: 'Request Timeout' },
      409 => { name: 'Conflict' },
      410 => { name: 'Gone' },
      411 => { name: 'Length Required' },
      412 => { name: 'Precondition Failed' },
      413 => { name: 'Payload Too Large' },
      414 => { name: 'Request-URI Too Long' },
      415 => { name: 'Unsupported Media Type' },
      416 => { name: 'Requested Range Not Satisfiable' },
      417 => { name: 'Expectation Failed' },
      418 => { name: 'I\'m a teapot' },
      421 => { name: 'Misdirected Request' },
      422 => { name: 'Unprocessable Entity' },
      423 => { name: 'Locked' },
      424 => { name: 'Failed Dependency' },
      426 => { name: 'Upgrade Required' },
      428 => { name: 'Precondition Required' },
      429 => { name: 'Too Many Requests' },
      431 => { name: 'Request Header Fields Too Large' },
      444 => { name: 'Connection Closed Without Response' },
      451 => { name: 'Unavailable For Legal Reasons' },
      499 => { name: 'Client Closed Request' },

      # 5×× Server Error
      500 => { name: 'Internal Server Error', code: :internal_server_error },
      501 => { name: 'Not Implemented',       code: :not_implemented },
      502 => { name: 'Bad Gateway' },
      503 => { name: 'Service Unavailable' },
      504 => { name: 'Gateway Timeout' },
      505 => { name: 'HTTP Version Not Supported' },
      506 => { name: 'Variant Also Negotiates' },
      507 => { name: 'Insufficient Storage' },
      508 => { name: 'Loop Detected' },
      510 => { name: 'Not Extended' },
      511 => { name: 'Network Authentication Required' },
      599 => { name: 'Network Connect Timeout Error' },
    }

    # e = Lux::Error.not_found('foo')
    CODE_LIST.each do |status, data|
      if data[:code]
        define_singleton_method(data[:code]) do |message=nil|
          error = new status, message

          if error.is_a?(Lux::Error::AutoRaise)
            Lux.current.response.status status
            Lux.log " error.#{data[:code]} in #{split_backtrace(error)[1].first.to_s.split(':in ').first}"
            raise error
          end

          error
        end
      end
    end

    class << self
      # template to show full error page
      def render *args
        error =
        if args.first.is_a?(String)
          new args[1], args.first
        else
          args.first
        end

        code = error.respond_to?(:code) ? error.code : 500
        Lux.current.response.status code

        lines = split_backtrace(error)

        %{<html>
            <head>
              <title>Lux error</title>
              <style>body { font-size: 14pt; font-family: sans-serif;} </style>
            </head>
            <body style="margin: 20px 20px 20px 140px; background-color:#fdd;">
              <img src="https://i.imgur.com/Zy7DLXU.png" style="width: 100px; position: absolute; margin-left: -120px;" />
              <h4>HTPP Error &mdash; <a href="https://httpstatuses.com/#{code}" target="http_error">#{code}</a></h4>
              <h3>#{error.class}</h3>
              <h3>#{error.message}</h3>
              #{error.respond_to?(:description) ? error.description : ''}
              <h4>Backtrace</h4>
              #{lines[1].to_ul}
              #{lines[2].to_ul}
            </body>
          </html>}
      end

      # render error inline or break in production
      def inline name, error=nil
        error ||= $!

        unless Lux.config(:dump_errors)
          key = log error
          render "Lux inline error: %s\n\nkey: %s" % [error.message, key]
        end

        name ||= 'Undefined name'
        msg    = error.message.to_s.gsub('","',%[",\n "]).gsub('<','&lt;')

        dmp = split_backtrace error

        dmp[1] = dmp[1].map { |_| _ = _.split(':', 3); '<b>%s</b> - %s - %s' % _ }

        log error

        <<~TEXT
          <pre style="color:red; background:#eee; padding:10px; font-family:'Lucida Console'; line-height:15pt; font-size:11pt;">
          <b style="font-size:110%;">#{name}</b>
          <xmp style="font-family:'Lucida Console'; line-height:15pt; font-size:12pt; font-weight: bold; margin-bottom: -5px;">#{dmp[0][0]}: #{dmp[0][1]}</xmp>
          #{dmp[1].join("\n")}

          #{dmp[2].join("\n")}
          </pre>
        TEXT
      end

      def report code, msg=nil
        e = Integer === code ? Lux::Error.new(code) : Lux::Error.send(code)
        e.message = msg if msg
        raise e
      end

      def log error
        Lux.config.error_logger.call error
      end

      def split_backtrace error
        # split app log rest of the log
        dmp = [[error.class, error.message], [], []]

        root = Lux.root.to_s

        (error.backtrace || caller).each do |line|
          line = line.sub(root, '.')
          dmp[line[0,1] == '.' ? 1 : 2].push line
        end

        dmp
      end

      def screen error
        return if Lux.env.test?
        data = split_backtrace(error)
        data[2] = data[2][0,5]
        ap data
      end
    end

    ###

    attr_accessor :name
    attr_accessor :message
    attr_accessor :description

    def initialize code_num, message=nil, description=nil
      self.code = code_num
      self.name = CODE_LIST[code_num][:name]
      self.description = description

      if Lux.config(:dump_errors) && !self.description
        parts = self.class.split_backtrace(self)
        self.description = %[
          <hr />
          <h4>Lux.config.dump_errors = true</h4>
          <pre>Lux.current.nav.path: <b>#{Lux.current.nav.path.join(' / ')}</b></pre>
          <pre>#{parts[1].join("\n")}</pre>
          <pre>#{parts[2].join("\n")}</pre>
        ]
      end

      @message = message || self.name
    end

    def code
      # 400 is a default
      @code || 400
    end

    def code= num
      @code = num.to_i

      raise 'Status code %s not found' % @code unless CODE_LIST[@code]
    end

    def render
      self.class.render message, code
    end
  end
end

