# Ref - opaque short ID generator + resolver used for primary keys / references.
#
# Apps register dispatch keys via `Ref.register(:ast, Asset)` and resolve with
# `Ref.load("ast-abc...")`. Apps may also reopen Ref to override `klass` or
# `public_link` if they need richer behaviour.

module Lux
module Utils
module Ref
  extend self

  LOWERCASE_KEYS ||= 'abcdefghijklmnopqrstuvwxyz0123456789'
  MIXEDCASE_KEYS ||= 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'

  REGISTRY ||= {}

  # validates the canonical 16-char form. accepts "key-ref" composite by
  # stripping the prefix before splitting on ':'.
  def is? text
    text.length == 16 && text =~ /^[a-z0-9]+$/
  end

  # Ref.generate                  -> 16-char lowercase+digits
  # Ref.generate(8)               -> 8-char lowercase+digits
  # Ref.generate(16, uppercase: true) -> 16-char mixed-case+digits
  def generate length = 16, uppercase: false
    keys = uppercase ? MIXEDCASE_KEYS : LOWERCASE_KEYS
    Array.new(length) { keys[rand(keys.length)] }.join
  end

  # Ref.register(:ast, Asset)
  def register key, klass
    REGISTRY[key.to_sym] = klass
  end

  # resolve dispatch key (":ast") to model class
  def klass key
    REGISTRY[key.to_sym] || raise("Unsupported ref key #{key.inspect}")
  end

  # Ref.load("ast-abc123...")   -> Asset.find('abc123...')
  # Ref.load(:ast, "abc123...")
  def load key_ref, ref = nil
    if ref
      key = key_ref
    else
      key, ref = key_ref.to_s.split('-')
    end
    klass(key).find(ref)
  end

  def public_link key_link
    object = self.load key_link rescue nil
    if object
      %[<a href="#{object.path}">#{object.name || '-'} (#{key_link.split('-')[0]})</a>]
    else
      %[<span class="gray">#{key_link}</span>]
    end
  end
end
end
end
