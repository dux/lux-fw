# Locale-keyed translations stored as jsonb, e.g. { "hr" => "Naslov", "en" => "Title" }.
# Accepts a Hash (locale => text), a JSON string, or a bare String (kept under the
# current locale, Lux.current.locale).
#
# On write it prunes stale translations: a single submitted locale whose text differs
# from the stored value drops the other locales (they need re-translation); if it is
# unchanged the stored siblings are kept. Multiple locales are stored as given.

class Lux::Type::TranslatedType < Lux::Type
  opts :default_locale, 'Locale for a bare string when Lux.current.locale is unset'

  error :en, :not_translated_type_error, 'value is not a translations hash'

  def coerce
    @value = clean(to_hash(value))

    error_for(:not_translated_type_error) unless @value.respond_to?(:keys)

    # single locale -> reconcile against what is stored
    if @value.size == 1
      locale, text = @value.first
      stored = clean(to_hash(stored_value))
      # unchanged: keep the other stored translations; changed: keep only this locale
      @value = stored.merge(@value) if stored[locale] == text
    end
    # multiple locales -> stored as given (no-op)
  end

  def default
    {}
  end

  def db_schema
    [:jsonb, {
      null:    false,
      default: '{}'
    }]
  end

  private

  # Hash passthrough; JSON string -> parsed hash; empty string -> {};
  # any other bare string -> { current_locale => string }.
  def to_hash val
    return {} if val.nil?
    return val unless val.is_a?(String)

    str = val.strip
    return {} if str.empty?

    if str.start_with?('{')
      JSON.parse(str) rescue error_for(:not_translated_type_error)
    else
      { current_locale => val }
    end
  end

  # stringify locale keys, drop blank translations
  def clean hash
    return {} unless hash.respond_to?(:each)
    hash.each_with_object({}) do |(locale, text), out|
      next if text.is_a?(String) && text.strip.empty?
      out[locale.to_s] = text
    end
  end

  def current_locale
    loc = Lux.current.locale if Lux.respond_to?(:current) && Lux.current
    loc = loc.presence || opts[:default_locale] || (Lux.locale.default rescue nil) || 'en'
    loc.to_s
  end
end
