# Minimal HTML-text escaping for haml `=` output. Escapes only `<` -> `&lt;`,
# which is all that stops the tokenizer from opening a tag in a text node. `&`,
# quotes and `>` are left readable on purpose:
#   - `>` never opens a tag on its own,
#   - quotes only matter inside attribute values, and
#   - `&` cannot re-trigger the tokenizer in a text node, so `&lt;script&gt;`
#     renders as visible text rather than executing.
#
# Attribute escaping is a SEPARATE haml path (Haml::Util.escape_html via
# attribute_builder) and stays full-entity - we deliberately do NOT touch it, so
# `%a{title: v}` still escapes quotes and cannot be broken out of.
#
# Values that answer html_safe? (Lux::Utils::SafeString from String#unsafe) are
# passed through raw. Active only when a template is built with
# escape_html: true + use_html_safe: true; haml then compiles `= v` to
# ::Haml::Util.escape_html_safe((v)).
module Haml
  module Util
    def self.escape_html_safe html
      html = html.to_s
      return html if html.respond_to?(:html_safe?) && html.html_safe?
      html.gsub('<', '&lt;')
    end
  end
end
