# Vendored from the `html-tag` gem and rewritten for Lux. Single canonical
# `tag(name, inner = nil, **attrs, &block)` signature; no top-level `def HtmlTag`;
# '_klass__sub' names expand to <div class="klass sub">. Top-level `HtmlTag`
# constant is preserved as an alias so existing call sites keep working.

require 'set'

module Lux
  module Utils
    module HtmlTag
      OPTS ||= { format: false }

      # ---- Class-level builders (`HtmlTag.div(...)`) ---------------------
      class << self
        # `HtmlTag.div(class: 'x') { ... }` -> rendered string.
        def method_missing(name, *args, **attrs, &block)
          return super if name.start_with?('to_')
          render_root(nil, name, *args, **attrs, &block)
        end

        def respond_to_missing?(name, include_private = false)
          !name.start_with?('to_') || super
        end

        # Explicit render entry. Replaces the old top-level `HtmlTag(:ul) { ... }`.
        def call(name = :div, inner = nil, **attrs, &block) = render_root(nil, name, inner, **attrs, &block)

        # Define `#tag` on `klass` itself, so it wins over a `tag` the class already
        # has (apps call it after `delegate :tag`); `include` would lose to that.
        def mixin(klass) = klass.define_method(:tag, instance_method(:tag))

        # Register a custom tag (or empty/void tag).
        def define(name, empty: false) = Inbound.define(name, empty: empty)

        # One-shot render of a single root node into a string.
        def render_root(context, name = :div, inner = nil, **attrs, &block)
          inbound = Inbound.new(context)
          inbound.tag(name, inner, **attrs, &block)
          inbound.render
        end
      end

      # ---- include support: `class Foo; include HtmlTag; end` ------------
      def tag(*args, **attrs, &block)
        return Proxy.new(self) if args.empty? && attrs.empty? && block.nil?
        HtmlTag.render_root(self, *args, **attrs, &block)
      end
    end
  end
end
