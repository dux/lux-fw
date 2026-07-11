module Lux
module Utils
  # String subclass that renders raw (unescaped) in haml `=` output. Produced by
  # String#unsafe. haml's escape_html_safe skips escaping for any value that
  # answers html_safe? == true, so marking a string this way opts it out of the
  # default `<` -> `&lt;` escaping.
  #
  # to_s must return self: escape_html_safe does `html = html.to_s` before the
  # html_safe? check, and String#to_s on a subclass returns a fresh plain String
  # - which would drop the marker and get escaped anyway. Pinning to_s keeps the
  # subclass through that call (same reason ActiveSupport::SafeBuffer pins to_s).
  class SafeString < String
    def html_safe?
      true
    end

    def to_s
      self
    end
  end
end
end
