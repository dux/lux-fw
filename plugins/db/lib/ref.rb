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

  # every model that declares an abbr; memoized after first scan
  def models
    @models ||= Sequel::Model.descendants.select { |klass| (klass.abbr rescue nil).present? }
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

# Nav integration kept here so core Nav stays free of Ref/plugin knowledge.
class Lux::Application::Nav
  # Resolve the URL's model ref to records and export them as @object + @<model>
  # ivars on the running app. A model matches by name, plural, or its abbr, in
  # two URL forms:
  #   /boards/<ref>  or  /boa/<ref>   segment right before the ref
  #   /boa:<ref>                      abbr:ref path-qs (params[:boa])
  #
  # Defaults to every model that declares an abbr; models without one are skipped.
  #
  # Example - GET /boards/abc123, with Board.abbr == :boa:
  #   nav.load_models
  #   # => @object == @board == Board.find('abc123'); returns [board]
  #
  # ivars: false -> return the objects without setting ivars
  # pqs:   false -> ignore the abbr:ref form (API: a `doc[...]` POST must not reach find)
  def load_models models = nil, ivars: true, pqs: true
    path :ref do |el|
      Lux::Utils::Ref.is?(el) ? el : nil
    end

    i      = path.index(:ref)
    seg    = (i && i > 0) ? path[i - 1].to_s : nil
    app    = Lux.current.var[:lux_app] if ivars
    models = Lux::Utils::Ref.models if models.nil?

    Array(models).filter_map do |klass|
      abbr = klass.abbr rescue nil
      next unless abbr.present?   # no abbr -> cannot be URL-exported
      name = klass.to_s.split('::').last.underscore

      value =
        if ref && seg && [name, name.pluralize, abbr.to_s].include?(seg)
          ref
        elsif pqs && (v = Lux.current.params[abbr]).is_a?(String) && v.present?
          # only the `abbr:ref` path-qs form yields a ref here; a nested form hash
          # (e.g. params[:doc] from a `doc[...]` POST when abbr == model name) is
          # not a ref and must not reach find()
          v
        end

      next unless value
      object = klass.find(value) or next

      if app
        app.instance_variable_set(:@object, object)
        app.instance_variable_set("@#{name}".to_sym, object)
      end
      object
    end
  end
end
