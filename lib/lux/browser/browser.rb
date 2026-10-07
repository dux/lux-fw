require 'erb'
require 'json'

module Lux
  # Lux::Browser - two roles in one class:
  #
  # 1) Class-level: server-side composer for the window.Lux client surface.
  #    Subsystems register JS modules; Lux::Browser.client_js(...) returns the
  #    composed bundle served at /_lux_/*.js. This is the framework client lib
  #    (csrf, fetch, sse, ...).
  #
  # 2) Instance-level: the master per-request object, accessed via lux.browser
  #    (instantiated by Lux::Current#browser). It owns the browser-facing pieces:
  #
  #      lux.browser.header           -> Lux::Browser::Header (<head> builder)
  #      lux.browser.html             -> Lux::Browser::Html (whole document, lux.render_html)
  #      lux.browser.window           -> Hash exported onto the client `window`
  #      lux.browser.window_script    -> <script> that writes the window hash
  #      lux.browser.bundle(:sse)     -> composed client JS bundle
  #      lux.browser.channel(user)    -> SSE channel publisher (== Lux.channel)
  #
  #    Header stays its own class; window is just a Hash. lux.header is a pointer
  #    to lux.browser.header.
  #
  # Example:
  #
  #   # bundling (boot time, in any subsystem)
  #   Lux::Browser.register :sse, file: 'assets/lux/sse.js'
  #   Lux::Browser.client_js(:sse)     # -> JS string
  #
  #   # per-request (in a controller / before-filter)
  #   lux.browser.header.title          'My page'
  #   lux.browser.window[:app]        = { cfg: { host: Lux.config.host } }
  #   lux.browser.channel(:notifications).push(message: 'Hello')
  class Browser
    @modules ||= {}

    # -- class-level: JS module bundler ---------------------------------------

    class << self
      def register name, file:
        @modules[name.to_sym] = file.to_s
      end

      def modules
        @modules.keys
      end

      def registered? name
        @modules.key?(name.to_sym)
      end

      def client_js *names
        selected =
          if names.empty? || names == [:all]
            @modules.keys
          else
            names.map(&:to_sym)
          end

        ordered = ([:core] + selected).uniq
        ordered.map { |n|
          path = @modules[n] or raise ArgumentError, "Lux::Browser: unknown module #{n.inspect} (registered: #{@modules.keys})"
          render File.expand_path(path, Lux.fw_root.to_s)
        }.join("\n")
      end

      private

      def render path
        # Modules are static JS; ERB is still supported for rare dynamic modules.
        ERB.new(File.read(path), trim_mode: '-').result(binding)
      end
    end

    # -- instance-level: the master per-request object -----------------------
    #
    # One per request (Lux::Current#browser). Lazily builds the parts below.

    # HTML <head> builder. Memoised, with a back-reference to this browser so
    # Header#render emits *this* request's window_script. lux.browser.header and
    # the lux.header pointer share one instance per request.
    def header
      @header ||= Header.new.tap { |h| h.browser = self }
    end

    # Whole-document builder behind lux.render_html (see Browser::Html).
    def html
      @html ||= Html.new.tap { |h| h.browser = self }
    end

    # Layout file path, set by the controller right before the layout renders.
    attr_accessor :layout

    # Identifies the layout + deploy the client is running. pjax sends it back
    # as x-pjax-layout; a match lets render_html answer with the region alone.
    def layout_id
      return unless layout
      @layout_id ||= "#{layout}:#{Lux::DEPLOY_ID}".md5[0, 10]
    end

    # pjax navigation from a page built with this same layout and deploy.
    def pjax?
      !!layout_id && Lux.current.request.env['HTTP_X_PJAX_LAYOUT'] == layout_id
    end

    # Per-request state exported onto the client `window`. A plain Hash with
    # unrestricted access - set whatever you want, then emit via #window_script.
    # The `:app` bucket is pre-seeded (it's the namespace window_script merges
    # into window.app), so you can write into it without a guard:
    #
    #   lux.browser.window[:app][:user] = current_user.export   # -> window.app.user
    #   lux.browser.window[:app][:cfg]  = { host: Lux.config.host }
    #   lux.browser.window[:foo]        = 123                    # -> window.foo (global)
    def window
      @window ||= { app: {} }
    end

    # Emit the window hash as a <script> tag. Two guarded lines run first:
    # `window.app` is bootstrapped so bundles can drop defensive guards, and
    # its volatile `page` bucket is reset so a pjax navigation never inherits
    # the previous page's payload. The `:app` key is then *merged* into
    # window.app (so cfg/current persist and the page reset survives unless app
    # provides its own page); any other top-level keys are assigned onto window.
    # Outside production an extra `app.lux` bucket carries framework debug state.
    # header.render emits it whole; render_html splits it into boot_script
    # (<head>) and state_script (pjax region).
    def window_script
      %[<script id="lux-state">#{(boot_lines + state_lines).join("\n")}</script>]
    end

    # <head> half of window_script for render_html: Lux client surface + the
    # window.app guard, before any bundle loads.
    def boot_script
      %[<script>#{boot_lines.join("\n")}</script>]
    end

    # Per-request half for render_html, emitted as the first child of the pjax
    # region so every navigation (full or body-only) refreshes it. Lux cfg is
    # repeated because csrf rotates with the session (login/logout).
    def state_script
      lines = [lux_cfg_line] + state_lines
      lines << 'window.noCache = true;' if Lux.current.no_cache?
      %[<script id="lux-state">#{lines.join("\n")}</script>]
    end

    # Composed framework client JS (delegates to the class-level bundler).
    #   lux.browser.bundle        -> all modules
    #   lux.browser.bundle(:sse)  -> core + sse
    def bundle *mods
      self.class.client_js(*mods)
    end

    # SSE channel publisher by name - same handle as the module-level
    # Lux.channel(name).
    def channel name
      Channel[name]
    end

    # Broadcast `data` on channel `name` (convenience for channel(name).push).
    def publish name, data
      Channel[name].push(data)
    end

    private

    # Lux client surface (csrf/host) must land before asset packs that define
    # Lux.fetch / Lux.subscribe - those packs no longer go through /_lux_/*.js ERB.
    def boot_lines
      lines = ['window.Lux = window.Lux || {};', lux_cfg_line, 'window.app = window.app || {};']
      lines << 'window.DEV = true;' if Lux.env.dev?
      lines
    end

    def lux_cfg_line
      lux_cfg = {
        csrf:   Lux.current.csrf,
        config: { host: Lux.config.host.to_s, locale: Lux.current.locale.to_s },
      }
      "Object.assign(window.Lux, #{js_safe(lux_cfg)});"
    end

    def state_lines
      app  = window[:app] || window['app']
      rest = window.reject { |k, _| k.to_s == 'app' }

      if (state = dev_state)
        app = (app || {}).merge(lux: state)
      end

      lines = ['window.app.page = {};']
      lines << "Object.assign(window.app, #{js_safe(app)});" if app && !app.empty?
      lines << "Object.assign(window, #{js_safe(rest)});"    unless rest.empty?
      lines
    end

    # Payload emitted as window.app.lux, nil in production (these are server
    # paths). `file_in_use` is the render trail for this request - templates,
    # cells and route blocks in the order Lux.current.files_in_use saw them.
    # The head is rendered by the layout, after the page template, so the page
    # files are already collected by the time this runs. `root` is what the
    # trail is relative to, so a dev tool can build an absolute path (the dev
    # menu turns it into a vscode://file/ link).
    def dev_state
      return if Lux.env.prod?

      files = Lux.current.files_in_use.to_a
      { root: Lux.root.to_s, file_in_use: files } if files.any?
    end

    # Escape </ to <\/ so a string value can't break out of the <script> tag.
    # It has to be a JSON escape, not an HTML entity: <script> content is not
    # entity-decoded, so &lt; would reach the client verbatim and corrupt any
    # value that legitimately contains a < or >.
    def js_safe value
      out = Lux.env.dev? ? value.to_jsonp : value.to_json
      out.gsub('</', '<\/')
    end
  end
end

# Self-register the core JS module.
Lux::Browser.register :core, file: 'assets/lux/core.js'
