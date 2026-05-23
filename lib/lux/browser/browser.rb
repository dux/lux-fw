require 'erb'
require 'json'

module Lux
  # Lux::Browser - two roles in one class:
  #
  # 1) Class-level: server-side composer for the window.Lux client surface.
  #    Subsystems register JS modules; Lux::Browser.client_js(...) returns the
  #    composed bundle served at /lux/*.js. This is the framework client lib
  #    (csrf, fetch, sse, ...).
  #
  # 2) Instance-level: per-request state accumulator, accessed via lux.browser.
  #    Chain-set arbitrary nested keys; emit as a <script> tag in the page
  #    head. Lands as window.<root> = {...} on the client. Separate window
  #    namespace from window.Lux on purpose; the user owns it (app config,
  #    bootstrap data, anything pjax wants to read).
  #
  # Example:
  #
  #   # bundling (boot time, in any subsystem)
  #   Lux::Browser.register :sse, file: 'assets/lux/sse.js'
  #   Lux::Browser.client_js(:sse)     # -> JS string
  #
  #   # per-request state (in a controller / before-filter)
  #   lux.browser.app.config.host  = Lux.config.host
  #   lux.browser.app.config.locale = lux.locale
  #   lux.browser.app.data.user    = current_user.to_h
  #
  #   # in the layout head
  #   != lux.browser.script_tag
  #   # -> <script id="lux-state">window.app ||= {};
  #         window.app.config ||= {};
  #         window.app.config.host = "...";
  #         ...</script>
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

    # -- instance-level: per-request state -----------------------------------

    def initialize
      @data = {}
    end

    # Any method becomes a top-level node. Chain further for nested keys.
    #
    #   lux.browser.app.config.host = 'x'    # window.app.config.host = "x"
    #   lux.browser.foo.bar          = 1     # window.foo.bar          = 1
    def method_missing name, *args
      n = name.to_s
      if n.end_with?('=')
        @data[n.chomp('=')] = args.first
      elsif args.empty?
        @data[n] ||= Node.new
      else
        super
      end
    end

    def respond_to_missing? _name, _include_private = false
      true
    end

    def [] key
      @data[key.to_s]
    end

    def []= key, value
      @data[key.to_s] = value
    end

    # Deep hash representation. Useful for tests / debugging.
    def to_h
      deep_hash @data
    end

    # Emit rule:
    #   * top-level keys (window.app, window.api, ...) get `||= {}` bootstrap
    #     so pjax re-renders preserve untouched buckets.
    #   * level-2 keys (window.app.config, window.app.data, ...) get an atomic
    #     `= JSON(subtree)` assignment - the whole bucket is replaced as one.
    #
    # When no state has been set, still emits the default namespace bootstrap
    # (Lux.config.browser_namespace, default 'app') so pjax has a stable target.
    def script_tag
      ns    = Lux.config[:browser_namespace] || 'app'
      lines = []

      if @data.empty?
        lines << "window.#{ns} ||= {};"
      else
        @data.each { |root, val| emit_root root.to_s, val, lines }
      end

      %[<script id="lux-state">#{lines.join("\n")}</script>]
    end

    private

    def deep_hash node
      node.each_with_object({}) do |(k, v), h|
        h[k] = v.is_a?(Node) ? v.to_h : v
      end
    end

    # Root (level-1): bootstrap with `||= {}` then assign each level-2 child.
    # A level-1 primitive (e.g. lux.browser.foo = 1) skips the bootstrap and
    # is emitted as one assignment.
    def emit_root name, value, lines
      target = "window.#{name}"

      if value.is_a?(Node)
        lines << "#{target} ||= {};"
        value.each do |sub_key, sub_value|
          serialised = sub_value.is_a?(Node) ? sub_value.to_h : sub_value
          lines << "#{target}.#{sub_key} = #{js_safe(serialised)};"
        end
      else
        lines << "#{target} = #{js_safe(value)};"
      end
    end

    # Escape </ to <\/ so a value containing a closing-script sequence can't
    # break out of the surrounding <script> tag.
    def js_safe value
      JSON.generate(value).gsub('</', '<\/')
    end

    # Auto-vivifying node. Same method_missing semantics as Browser itself.
    # `each` and friends are defined explicitly so method_missing doesn't
    # capture them as new keys when the framework iterates internally.
    class Node
      def initialize
        @data = {}
      end

      def each &block
        @data.each(&block)
      end

      def [] key
        @data[key.to_s]
      end

      def []= key, value
        @data[key.to_s] = value
      end

      def to_h
        @data.each_with_object({}) do |(k, v), h|
          h[k] = v.is_a?(Node) ? v.to_h : v
        end
      end

      def empty?
        @data.empty?
      end

      def method_missing name, *args
        n = name.to_s
        if n.end_with?('=')
          @data[n.chomp('=')] = args.first
        elsif args.empty?
          @data[n] ||= Node.new
        else
          super
        end
      end

      def respond_to_missing? _name, _include_private = false
        true
      end
    end
  end
end

# Self-register the core JS module.
Lux::Browser.register :core, file: 'assets/lux/core.js'
