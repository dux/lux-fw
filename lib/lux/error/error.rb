# frozen_string_literal: true

# Lux::Error - thin exception class. No HTTP status, no registry, no shortcuts.
# HTTP status is set on lux.response by `Lux.error CODE, msg` (see error/lux_adapter.rb),
# not carried on the exception itself. `Lux.error` builds the exception; the caller raises it.
#
# Static helpers below (.inline, .format) handle error display.
module Lux
  class Error < StandardError
    class << self
      # Render error inline (e.g. embedded in a template error fallback).
      def inline object, msg = nil
        error = object.is_a?(String) ? nil : object

        HtmlTag.pre(class: 'lux-inline-error', style: 'background: #fff; margin-top: 10px; padding: 10px; font-size: 14px; border: 2px solid #600; line-height: 20px;') do |n|
          if error && Lux.debug?
            n.button 'Copy', class: 'btn', style: 'float: right;', onclick: copy_onclick
            n.tag :textarea, format(error, message: true), style: 'display:none;'
            n.push format(error, html: true, message: true)
          end
        end
      end

      # Format error backtrace for CLI/screen output.
      # Local app lines start with ./ , gem/global lines keep full path.
      #   format error, html: true, message: true, gems: true
      def format error, opts = {}
        unless error && error.backtrace
          lines = []
          lines << "[#{error.class}] #{error.message}" if error && opts[:message] == true
          lines << 'no backtrace present'
          return opts[:html] ? lines.join($/).html_escape : lines.join($/)
        end

        root = Lux.root.to_s

        lines = ["[#{error.class}] #{error.message}"]
        lines += error
          .backtrace
          .map { |line| '  ' + line.sub(root, '.') }
          .select { |line| opts[:gems] == false ? line[0, 3] == '  .' : true }

        if opts[:html]
          # messages and paths are text (a Rack error echoes the param name)
          lines.map!(&:html_escape)
          lines[0] = "<b>%s</b>\n" % lines[0]
          lines.map! { |line| line[0, 3] == '  .' ? "<b>#{line}</b>" : line }
        end

        lines.shift unless opts[:message] == true

        if (url = current_url)
          url_line = opts[:html] ? %[<b>URL: <a href="#{url.html_escape}">#{url.html_escape}</a></b>\n] : "URL: #{url}"
          lines.unshift url_line
        end

        opts[:html] ? Lux::SafeString.new(lines.join($/)) : lines.join($/)
      end

      # Dev-only "Copy for LLM" button. A hidden textarea carries an
      # LLM-ready paste (NAME: DATA lines); the button copies it. Returns ''
      # outside dev, so it can be dropped straight into any error template.
      def copy_button error, status = nil
        return '' unless Lux.env.dev?

        HtmlTag.span do |n|
          n.button 'Copy for LLM', class: 'btn', style: 'cursor: pointer;', onclick: copy_onclick
          n.tag :textarea, copy_payload(error, status), style: 'display:none;'
        end
      end

      private

      # Onclick for the textarea-sibling copy buttons. Delegates to the app-wide
      # $.copyText helper, which copies via execCommand and so works on plain-HTTP
      # dev hosts (e.g. lvh.me) where navigator.clipboard is undefined.
      def copy_onclick
        "$.copyText(this.nextElementSibling.value);this.innerText='Copied!'"
      end

      # LLM-ready error paste, one "NAME: DATA" per line.
      def copy_payload error, status = nil
        lines = []
        lines << "URL: #{current_url}" if current_url
        if status
          name = ::Rack::Utils::HTTP_STATUS_CODES[status.to_i] || 'Error'
          lines << "STATUS: #{status} #{name}".strip
        end
        lines << "MESSAGE: #{error.message}"
        if error.respond_to?(:backtrace) && error.backtrace
          bt = error.backtrace.first(40).map { |line| line.sub(Lux.root.to_s, '.') }.join($/)
          lines << "BACKTRACE:\n#{bt}"
        end
        lines.join($/)
      end

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
