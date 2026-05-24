require_relative './html_tag'
require_relative './inbound'

# Proxy used for `tag.div(...)` chained calls inside a host instance.
# Wraps a single-use Inbound; each method call renders that one tag and
# returns the rendered string.
module Lux
  module Utils
    module HtmlTag
      class Proxy
        def initialize(scope = nil)
          @inbound = Lux::Utils::HtmlTag::Inbound.new(scope)
        end

        def method_missing(name, *args, **attrs, &block)
          @inbound.public_send(name, *args, **attrs, &block)
          @inbound.render
        end

        def respond_to_missing?(name, include_private = false)
          @inbound.respond_to?(name, include_private) || super
        end
      end
    end
  end
end

# Back-compat top-level alias. Lets existing `HtmlTag.div(...)`, `HtmlTag::Inbound`,
# and `include HtmlTag` keep working without changes.
HtmlTag = Lux::Utils::HtmlTag unless defined?(HtmlTag) && HtmlTag.equal?(Lux::Utils::HtmlTag)
