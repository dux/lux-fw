# Human API guide, generated from the same introspection document as every
# other export.
#
#   Lux::Api::Guide.markdown(@api, mount_on: '/api')  # source markdown
#   Lux::Api::Guide.html(@api, mount_on: '/api')      # rendered HTML page
#
# The markdown lives in assets/api/guide.md.erb; the HTML is that markdown
# rendered server-side by Lux::Utils::Markdown and dropped into the
# self-contained shell assets/api/guide.html.

module Lux
  class Api
    module Guide
      extend self

      MD_TEMPLATE ||= Lux.fw_root.join('assets/api/guide.md.erb').to_s
      HTML_SHELL  ||= Lux.fw_root.join('assets/api/guide.html').to_s

      def markdown api = nil, mount_on: nil
        ErbView.new(api, mount_on: mount_on).render(MD_TEMPLATE)
      end

      def html api = nil, mount_on: nil
        view    = ErbView.new(api, mount_on: mount_on)
        mount   = view.mount_on
        host    = view.request ? view.request.host : 'API'
        content = Lux::Utils::Markdown.to_html view.render(MD_TEMPLATE)

        File.read(HTML_SHELL)
            .gsub('{{title}}', "#{host} API")
            .gsub('{{raw}}', "#{mount}/sys/md")
            .gsub('{{explorer}}', "#{mount}/sys/web")
            .sub('{{content}}', content)
      end
    end
  end
end
