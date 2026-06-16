module Lux
  module Render
    # HTML <head> builder. One instance per request, lazily created by
    # Lux::Current#header. Accumulates meta tags, links and flags via a
    # chained DSL, then emits the head HTML via #render.
    #
    # Usage:
    #   lux.header.title       'My page'
    #   lux.header.description 'short summary'
    #   lux.header.canonical   'https://example.com/page'
    #   = lux.header.render do |page|
    #     = asset 'main.css'
    #
    # Setter/getter conflation: most attribute methods double as readers
    # when called without an argument (`header.title 'foo'` sets;
    # `header.title` returns). The same slot is also writable via
    # `header.title = 'foo'`.
    class Header
      # Meta-name prefixes that emit `property=` instead of `name=`
      # (RDFa Open Graph extensions). All others, including `twitter:`,
      # use `name=` per Twitter Cards documentation.
      META_PROPERTY_PREFIXES ||= %w[og: fb: article: book: profile: video: music:].freeze

      MAX_TITLE_LENGTH       ||= 100
      MAX_DESCRIPTION_LENGTH ||= 140

      DEFAULT_VIEWPORT       ||= 'width=device-width, initial-scale=1'
      DEFAULT_OG_TYPE        ||= 'website'

      def initialize app = nil
        @meta      = {}
        @links     = []
        @window    = {}
        @site_name = app
      end

      # Per-request JS bootstrap state. Populate it (`window[:user] = ...`)
      # and emit it via #window_script. #render only guarantees `window.app`
      # exists (before any bundle); the data itself is emitted inside the page
      # body (pjax region) so it refreshes on navigation.
      def window
        @window
      end

      # <script> that merges the accumulated #window data into window.app.
      # Place it inside the pjax-swapped region so it re-runs on navigation.
      def window_script
        return '' if @window.empty?
        %[<script>window.app = Object.assign(window.app || {}, #{@window.to_jsonp});</script>]
      end

      # -- meta / title / description ------------------------------------

      # Arbitrary meta tag. `value.to_s` is stored, so passing nil writes
      # the literal string "nil" - use a fresh Header to "unset".
      def meta name, value
        @meta[name.to_s] = value.to_s
      end

      # Sets <title> + og:title (no arg returns the title slot).
      # Trimmed to MAX_TITLE_LENGTH.
      def title data = nil
        return @title unless data.present?
        @meta['og:title'] = @title = data.trim(MAX_TITLE_LENGTH)
      end
      alias_method :title=, :title

      # Sets description + og:description + twitter:description
      # (no arg returns the current description). Trimmed to
      # MAX_DESCRIPTION_LENGTH.
      def description data = nil
        return @meta['description'] unless data.present?
        data = data.trim(MAX_DESCRIPTION_LENGTH)
        @meta['description']         = data
        @meta['og:description']      = data
        @meta['twitter:description'] = data
      end
      alias_method :description=, :description

      # Sets og:url (no arg returns it). Does NOT add a canonical <link>;
      # call #canonical for that.
      def url data = nil
        return @url unless data.present?
        @meta['og:url'] = @url = data
      end
      alias_method :url=, :url

      def site_name name = nil
        return @site_name unless name
        @site_name = name
      end

      def type kind = nil
        return @og_type unless kind
        @og_type = kind
      end

      # Sets og:image + twitter:image + twitter:card. Relative URLs
      # ("/og.png") are made absolute via current request host.
      def image src = nil
        return @meta['og:image'] unless src.present?
        src = "#{Lux.current.nav.base}#{src}" if src.start_with?('/')
        @meta['og:image']      = src
        @meta['twitter:image'] = src
        @meta['twitter:card']  = 'summary_large_image'
      end
      alias_method :image=, :image

      def locale name
        meta 'og:locale', name
      end

      # Accepts Time / DateTime (anything with #iso8601) or a String/other
      # that gets to_s'd.
      def revised date_time
        stamp = date_time.respond_to?(:iso8601) ? date_time.iso8601 : date_time.to_s
        meta :revised, stamp
      end

      # -- <link> entries ------------------------------------------------

      def link rel, href
        @links.push '<link rel="%s" href="%s" />' % [rel, href]
      end

      # Emits <link rel="canonical"> and sets og:url. Note: does not
      # update the `url` reader slot - call #url separately if you also
      # want `header.url` to read the canonical href back.
      def canonical href
        @links.push '<link rel="canonical" href="%s" />' % href
        meta 'og:url', href
      end

      def preload resource
        type = 'font/%s' % resource.split('.').last
        @links.push %[<link rel="preload" href="#{resource}" as="font" type="#{type}" crossorigin="anonymous" />]
      end

      def rss url, title = nil
        @links.push %[<link rel="alternate" type="application/rss+xml" title="#{title || 'RSS feed'}" href="#{url}" />]
      end

      def sitemap href
        @links.push %[<link rel="sitemap" type="application/xml" title="Sitemap" href="#{href}" />]
      end

      # -- robots flags --------------------------------------------------

      def noindex;  @noindex  = true; end
      def nofollow; @nofollow = true; end

      # -- output --------------------------------------------------------

      # Emits the full <head> HTML.
      #
      # Side effect: writes the `x-robots-tag` response header. Idempotent
      # if called twice (same value), but designed to be called exactly
      # once per request from the layout's <head> block.
      #
      # The optional block is yielded `CdnAsset` (so layouts can call
      # `el.postwind`, `el.url '...'` etc.) and `self` as a second arg;
      # its return value is appended after the framework's meta/link tags -
      # used in Haml layouts to inject asset and font tags.
      def render
        extra = yield(CdnAsset, self) if block_given?

        apply_robots_header

        @meta['og:type']      = @og_type || DEFAULT_OG_TYPE
        @meta['viewport']     ||= DEFAULT_VIEWPORT
        @site_name            ||= Lux.config.app.name
        @meta['og:site_name'] = @site_name

        title_text = @title ? "#{@title} | #{@site_name}" : @site_name
        title_text = ::Rack::Utils.escape_html title_text.to_s.remove_tags

        meta_tags = ['<meta charset="UTF-8" />']
        @meta.each do |key, value|
          next unless value
          attr_name = property?(key) ? :property : :name
          meta_tags.push %[<meta #{attr_name}="#{key}" content="#{::Rack::Utils.escape_html value.to_s}" />]
        end

        out  = meta_tags.sort
        out += @links
        # Guarantee window.app exists before any bundle loads, so component
        # code can drop defensive `window.app ||= {}` guards. Per-request
        # data is assigned later, in the page body.
        boot = ['window.app = window.app || {};']
        boot.push 'window.DEV = true;' if Lux.env.dev?
        out.push %[<script>#{boot.join(' ')}</script>]
        out.push extra if extra

        if Lux.current.no_cache?
          out.push %[<script>window.noCache = true;</script>]
        end

        out.push %[<title>#{title_text}</title>]

        # Indent everything to fit a Haml `%head` block and collapse
        # blank lines left by skipped @meta values.
        ('  ' + out.join("\n")).gsub("\n<", "\n  <").gsub(/\n\s*\n/, "\n")
      end

      private

      def apply_robots_header
        robots = []
        robots.push @noindex  ? 'noindex, noarchive' : :index
        robots.push @nofollow ? :nofollow            : :follow
        value = robots.join(', ')
        meta :robots, value
        Lux.current.response.header 'x-robots-tag', value
      end

      def property? key
        META_PROPERTY_PREFIXES.any? { |p| key.start_with?(p) }
      end
    end
  end
end
