# frozen_string_literal: true

# Lux::Error - thin exception class. No HTTP status, no registry, no shortcuts.
# HTTP status is set on lux.response by `Lux.error CODE, msg` (see error/lux_adapter.rb),
# not carried on the exception itself.
#
# Static helpers below (.render, .inline, .format) handle error display.
module Lux
  class Error < StandardError
    class << self
      # Last-resort framework chrome. Reached only when there's no Lux.app
      # rescue_from and no controller :error. Reads status from lux.response.
      def render error
        error = StandardError.new(error) if error.is_a?(String)

        code  = Lux.current.response.status.to_i
        code  = 500 if code < 400
        Lux.current.response.status code
        name  = ::Rack::Utils::HTTP_STATUS_CODES[code] || 'Error'

        Lux.current.response.body(
          HtmlTag.html do |n|
            n.tag(:head) do |n|
              n.title 'Lux error'
            end
            n.tag(:body, style: "margin: 20px 20px 20px 140px; background-color:#fdd; font-size: 14pt; font-family: sans-serif;") do |n|
              n.img src: "https://i.imgur.com/Zy7DLXU.png", style: "width: 100px; position: absolute; margin-left: -120px;"
              n.h4 do |n|
                n.push %[HTTP Error &mdash; <a href="https://httpstatuses.com/#{code}" target="http_error">#{code}</a>]
                n.push %[ &dash; #{name}]
              end
              n.push inline(error)
            end
          end
        )
      end

      # Render error inline (e.g. embedded in a template error fallback).
      def inline object, msg = nil
        error, message = if object.is_a?(String)
          [nil, object]
        else
          [object, object.message]
        end

        message = message.to_s.gsub('","', %[",\n "]).gsub('<', '&lt;')

        HtmlTag.pre(class: 'lux-inline-error', style: 'background: #fff; margin-top: 10px; padding: 10px; font-size: 14px; border: 2px solid #600; line-height: 20px;') do |n|
          if error && Lux.mode.errors?
            plain = format(error, message: true).gsub('&', '&amp;').gsub('<', '&lt;')
            n.button 'Copy', class: 'btn', style: 'float: right;',
              onclick: "navigator.clipboard.writeText(this.nextElementSibling.value);this.innerText='Copied'"
            n.tag :textarea, plain, style: 'display:none;'
            n.push format(error, html: true, message: true)
          end
        end
      end

      # Format error backtrace for CLI/screen output.
      # Local app lines start with ./ , gem/global lines keep full path.
      #   format error, html: true, message: true, gems: true
      def format error, opts = {}
        return ['no backtrace present'] unless error && error.backtrace

        root = Lux.root.to_s

        lines = ["[#{error.class}] #{error.message}"]
        lines += error
          .backtrace
          .map { |line| '  ' + line.sub(root, '.') }
          .select { |line| opts[:gems] == false ? line[0, 3] == '  .' : true }

        if opts[:html]
          lines[0] = "<b>%s</b>\n" % lines[0]
          lines.map! { |line| line[0, 3] == '  .' ? "<b>#{line}</b>" : line }
        end

        lines.shift unless opts[:message] == true

        if (url = current_url)
          url_line = opts[:html] ? %[<b>URL: <a href="#{url}">#{url}</a></b>\n] : "URL: #{url}"
          lines.unshift url_line
        end

        lines.join($/)
      end

      private

      # Current request URL if available, nil in non-HTTP contexts.
      def current_url
        return nil unless Thread.current[:lux]
        Lux.current.request.url
      rescue StandardError
        nil
      end
    end
  end
end
