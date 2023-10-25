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
      400 => { name: 'Bad Request',        short: :bad_request },
      401 => { name: 'Unauthorized',       short: :unauthorized },
      402 => { name: 'Payment Required',   short: :payment_required },
      403 => { name: 'Forbidden',          short: :forbidden },
      404 => { name: 'Document Not Found', short: :not_found },
      405 => { name: 'Method Not Allowed', short: :method_not_allowed },
      406 => { name: 'Not Acceptable',     short: :not_acceptable },
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
      500 => { name: 'Internal Server Error', short: :internal_server_error },
      501 => { name: 'Not Implemented',       short: :not_implemented },
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
      if data[:short]
        define_singleton_method(data[:short]) do |message=nil|
          error = Lux::Error.new status, message

          if self == Lux::Error::AutoRaise
            Lux.current.response.status status
            Lux.log " error.#{data[:code]} in #{Lux.app_caller}"
            raise error
          end

          error
        end
      end
    end

    class << self
      # template to show full error page
      def render error
        error = StandardError.new(error) if error.is_a?(String)

        code = error.respond_to?(:code) ? error.code : 500
        Lux.current.response.status code

        Lux.current.response.body(
          HtmlTag.html do |n|
            n.head do |n|
              n.title 'Lux error'
            end
            n.body style: "margin: 20px 20px 20px 140px; background-color:#fdd; font-size: 14pt; font-family: sans-serif;" do |n|
              n.img src: "https://i.imgur.com/Zy7DLXU.png", style: "width: 100px; position: absolute; margin-left: -120px;"
              n.h4 do |n|
                n.push %[HTTP Error &mdash; <a href="https://httpstatuses.com/#{code}" target="http_error">#{code}</a>]
                n.push %[ &dash; #{error.name}] if error.respond_to?(:name)
              end
              n.push inline error
            end
          end
        )
      end

      # render error inline
      def inline object, msg = nil
        error, message = if object.is_a?(String)
          [nil, object]
        else
          [object, object.message]
        end

        error_key = error ? log(error) : nil
        message = message.to_s.gsub('","',%[",\n "]).gsub('<','&lt;')

        HtmlTag.pre(class: 'lux-inline-error', style: 'background: #fff; margin-top: 10px; padding: 1px 10px 10px 10px; font-size: 14px; border: 2px solid #600; line-height: 20px;') do |n|
          n.h3 '%s : %s' % [error.class, message]
          n.p msg if msg
          n.p 'Key: %s' % error_key if error_key
          n.p 'Description: %s' % error.description if error && error.respond_to?(:description) && error.description

          if error && Lux.env.show_errors?
            n.hr
            n.push mark_backtrace(error, html: true).join("\n")
          end
        end
      end

      # clear osx screen :)
      def clear_screen
        last = (Thread.current[:_lux_clear_screen] ||= 1.day.ago)
        if last < Time.now - 5
          Thread.current[:_lux_clear_screen] = Time.now
          print "\e[H\e[2J\e[3J"
        end
      end

      # prepare backtrace for better render
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

      def mark_backtrace error, html: false
        return ['no backtrace present'] unless error && error.backtrace

        root = Lux.root.to_s

        error
          .backtrace
          .map do |line|
            path = line.split(':in').first
            path = path.sub(/^\.\//, root+'/')

            edit = html ? %[ &bull; <a href="subl://open?url=file:/#{path}">edit</a>] : ''
            line = line.sub(root, '.')
            (line[0,1] != '/' ? (html ? line.tag(:b) : line) : line) + edit
          end
      end

      # show in stdout
      def screen error
        return unless Lux.env.show_errors?

        data = split_backtrace(error)
        data[2] = data[2][0,5]
        ap data
      end

      def log err
        if Lux.config.error_logger
          Lux.config.error_logger.call err
        end
      end
    end

    ###

    attr_accessor :message

    def initialize *args
      if args.first.is_a?(Integer)
        self.code    = args.shift
      end

      self.message = args.shift || name
    end

    def code
      # 400 is a default
      @code || 400
    end

    def name
      CODE_LIST[code][:name]
    end

    def code= num
      @code = num.to_i

      raise 'Status code %s not found' % @code unless CODE_LIST[@code]
    end
  end
end
