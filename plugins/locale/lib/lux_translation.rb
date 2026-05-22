# Database-backed store for Lux::Locale. Wired in by plugins/locale/loader.rb
# when ApplicationModel is available.
#
# Each row is one translation, keyed by (namespace, key, locale). The plugin
# sets `Lux::Locale.store = LuxTranslation`, so `Lux.locale.t` reads through
# `.get` and `Lux.locale.set` writes through `.set`.

class LuxTranslation < ApplicationModel
  schema do
    namespace String, max: 100, index: true
    key       String, max: 255, index: true
    locale    String, max: 10,  index: true
    translation :text
    created_at Time
    updated_at Time
  end

  class << self
    # Lux::Locale store contract.
    #
    #   LuxTranslation.get(:en, :users, 'welcome')   # explicit ns + key
    #   LuxTranslation.get(:en, 'users.welcome')     # full dotted key, split on first '.'
    #
    # Returns the stored string or nil.
    def get locale, ns_or_key, subkey = nil
      ns, subkey = subkey.nil? ? ns_or_key.to_s.split('.', 2) : [ns_or_key, subkey]
      raise ArgumentError, "key must be namespaced (e.g. 'users.welcome')" if subkey.nil? || subkey.empty?

      first(locale: locale.to_s, namespace: ns.to_s, key: subkey.to_s)&.translation
    end

    # Upsert by (locale, namespace, key). All 4 args required.
    def set locale, ns, key, value
      attrs = { locale: locale.to_s, namespace: ns.to_s, key: key.to_s }
      now   = Time.now

      if row = first(attrs)
        row.update translation: value.to_s, updated_at: now
      else
        create attrs.merge(translation: value.to_s, created_at: now, updated_at: now)
      end
    end
  end
end
