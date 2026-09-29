module Lux
  module Utils
    # Server-side Markdown -> HTML via Commonmarker (CommonMark + GFM).
    # Thin wrapper so call sites do not repeat the extension/render options.
    module Markdown
      extend self

      # GFM extensions the API guide relies on. Kept as one frozen hash so
      # every caller renders the same dialect.
      EXTENSIONS ||= {
        table:         true,
        strikethrough: true,
        autolink:      true,
        tasklist:      true,
        footnotes:     true
      }.freeze

      # Raw HTML is escaped (visible as text) by default; unsafe: true lets it
      # through. Comrak would otherwise drop it with an "omitted" comment.
      def to_html text, unsafe: false
        Commonmarker.to_html text.to_s, options: {
          render:    { unsafe: unsafe, escape: !unsafe },
          extension: EXTENSIONS
        }
      end
      alias :render :to_html
    end
  end
end
