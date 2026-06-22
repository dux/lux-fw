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
  #      lux.browser.window           -> Hash exported onto the client `window`
  #      lux.browser.window_script    -> <script> that writes the window hash
  #      lux.browser.bundle(:sse)     -> composed client JS bundle
  #      lux.browser.channel(:foo)    -> SSE channel publisher (== Lux.channel)
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
    def window_script
      app  = window[:app] || window['app']
      rest = window.reject { |k, _| k.to_s == 'app' }

      lines = ['window.app = window.app || {};', 'window.app.page = {};']
      lines << "Object.assign(window.app, #{js_safe(app)});" if app && !app.empty?
      lines << "Object.assign(window, #{js_safe(rest)});"    unless rest.empty?

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

    # Escape </ to <\/ so a string value can't break out of the <script> tag.
    def js_safe value
      out = Lux.env.dev? ? value.to_jsonp : value.to_json
      out.gsub('<', '&lt;').gsub('>', '&rt;')
    end
  end
end

# Self-register the core JS module.
Lux::Browser.register :core, file: 'assets/lux/core.js'
