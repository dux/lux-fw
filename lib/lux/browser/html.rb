module Lux
  class Browser
    # Whole-document builder behind lux.render_html. The block's own output is
    # the <head> extras (assets, links); el.body captures the pjax region and
    # el.footer optional chrome after it.
    #
    #   = lux.render_html do |el|
    #     = el.assets :app
    #     = el.body class: 'bg-white' do
    #       = yield
    #     = el.footer class: 'small' do
    #       ...
    #
    # Slots must use `=`: Haml captures the block only then, `-` would write it
    # straight into the head.
    #
    # The region is always <div class="pjax" id="main"> with the state script as
    # its first child. When pjax asks for the layout the client already runs
    # (x-pjax-layout == layout_id) only <title> + region are returned - head and
    # footer are not built. <body> and <footer> attributes are not refreshed by
    # pjax, put per-page ones inside the region.
    class Html
      attr_accessor :browser

      def render lang: nil
        head = yield(self).to_s
        raise ArgumentError, 'lux.render_html: el.body was never called' unless @region

        if (id = browser.layout_id)
          Lux.current.response.header 'x-pjax-layout', id
          Lux.current.response.header 'vary', 'x-pjax-layout'
        end

        return %[<title>#{header.full_title}</title>\n#{@region}] if browser.pjax?

        lang ||= Lux.current.locale.to_s.presence || 'en'

        out = header.tags
        out.push %[<meta name="pjax-layout" content="#{id}" />] if id
        out.push browser.boot_script
        out.push head.strip if head.present?
        out.push %[<title>#{header.full_title}</title>]

        [
          '<!DOCTYPE html>',
          %[<html lang="#{lang.to_s.tr('_', '-')}">],
          "<head>\n#{out.join("\n")}\n</head>",
          (@body_attrs || {}).tag(:body, "\n#{@region}\n#{@footer}"),
          '</html>',
        ].join("\n")
      end

      # attrs go on <body>
      def body **attrs
        @body_attrs = attrs
        @region = %[<div class="pjax" id="main">#{browser.state_script}#{yield}</div>]
        nil
      end

      # attrs go on the <footer> wrapper; skipped on pjax
      def footer **attrs
        @footer = attrs.tag(:footer, yield) unless browser.pjax?
        nil
      end

      # el.icon false leaves out the favicon plugin's icon links
      def icon value
        header.icon value
        nil
      end

      # page title, same as lux.header.title; overrides one set by the page template
      def title text
        header.title text
        nil
      end

      def asset name, opts = {}
        browser.pjax? ? '' : CdnAsset.url(name, opts)
      end

      # = el.assets :app, :admin -> app.css, admin.css, app.js, admin.js
      def assets *names
        return '' if browser.pjax?
        %w[css js].flat_map { |ext| names.map { CdnAsset.url "#{_1}.#{ext}" } }.compact.join("\n")
      end

      # <link rel="preconnect">, opts are extra attrs (crossorigin: '')
      def preconnect url, opts = {}
        browser.pjax? ? '' : { rel: 'preconnect', href: url }.merge(opts).tag(:link)
      end

      # fonts.gstatic.com serves fonts over CORS, so its preconnect needs crossorigin
      def google_fonts_preconnect
        [preconnect('https://fonts.googleapis.com'), preconnect('https://fonts.gstatic.com', crossorigin: '')].join("\n")
      end

      private

      def header
        browser.header
      end
    end
  end
end
