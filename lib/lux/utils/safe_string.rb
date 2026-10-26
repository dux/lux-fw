require 'erb'

module Lux
  # Markup a template prints as is (html_safe? is true). Appending plain text
  # escapes it first, so `safe + user_text` stays safe. Any other String method
  # (gsub, strip, interpolation) returns a plain String - treated as text again.
  class SafeString < ::String
    # value as markup: kept when already safe, entity-escaped otherwise
    def self.escape value
      value = value.to_s
      value.html_safe? ? value : ERB::Util.html_escape(value)
    end

    # join parts into one safe string, escaping the parts that are plain text
    def self.join parts, separator = ''
      new parts.map { escape(_1) }.join(separator)
    end

    def html_safe?
      true
    end

    # String#to_s on a subclass returns a plain String copy
    def to_s
      self
    end

    def html_unsafe(**)
      self
    end

    # already markup; escaping again would double-escape
    def html_escape = self

    def + other
      SafeString.new(super(SafeString.escape(other)))
    end

    def concat *others
      super(*others.map { SafeString.escape(_1) })
    end

    def << other
      concat other
    end

    # Haml's output buffer (see Lux::Template::HamlBuffer). Haml escapes before
    # it appends, so << is raw here; the buffer, and so any template block
    # that hands it back, is markup.
    class Buffer < SafeString
      def concat *parts
        ::String.instance_method(:concat).bind_call(self, *parts)
      end

      def << part
        concat part
      end
    end
  end
end
