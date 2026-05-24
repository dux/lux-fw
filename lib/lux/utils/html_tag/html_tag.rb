# Vendored from the `html-tag` gem and rewritten for Lux. Single canonical
# `tag(name, inner = nil, **attrs, &block)` signature; no top-level `def HtmlTag`
# pollution; no `_klass__sub` method-missing sugar. Top-level `HtmlTag` constant
# is preserved as an alias so existing call sites keep working.

require 'set'

module Lux
  module Utils
    module HtmlTag
      extend self

      OPTS ||= { format: false }

      # ---- Class-level builders (`HtmlTag.div(...)`) ---------------------

      # `HtmlTag.div(class: 'x') { ... }` -> rendered string.
      def method_missing(name, *args, **attrs, &block)
        if self.equal?(::HtmlTag)
          render_root(nil, name, *args, **attrs, &block)
        else
          super
        end
      end

      def respond_to_missing?(_name, _include_private = false)
        self.equal?(::HtmlTag)
      end

      # Explicit render entry. Replaces the old top-level `HtmlTag(:ul) { ... }`.
      def call(name = :div, inner = nil, **attrs, &block)
        render_root(nil, name, inner, **attrs, &block)
      end

      # Define `#tag` on `klass` without polluting its ancestors chain.
      # Replaces the old `HtmlTag self` form.
      def mixin(klass)
        klass.define_method(:tag) do |*args, **attrs, &block|
          if args.empty? && attrs.empty? && block.nil?
            Lux::Utils::HtmlTag::Proxy.new(self)
          else
            Lux::Utils::HtmlTag.render_root(self, *args, **attrs, &block)
          end
        end
      end

      # Register a custom tag (or empty/void tag).
      def define(name, empty: false)
        Inbound.define(name, empty: empty)
      end

      # ---- include support: `class Foo; include HtmlTag; end` ------------
      # Instances get `tag` - same semantics as `mixin`.
      def tag(*args, **attrs, &block)
        if args.empty? && attrs.empty? && block.nil?
          Proxy.new(self)
        else
          Lux::Utils::HtmlTag.render_root(self, *args, **attrs, &block)
        end
      end

      # ---- internal ------------------------------------------------------
      # One-shot render of a single root node into a string.
      def render_root(context, name = :div, inner = nil, **attrs, &block)
        inbound = Inbound.new(context)
        inbound.tag(name, inner, **attrs, &block)
        inbound.render
      end
    end
  end
end
