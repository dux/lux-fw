# Lux::Locale - namespaced flat-file translation lookup, with optional
# DB-backed store (LuxTranslation) when ApplicationModel is available.
#
# Enable in config.yaml:
#   plugins:
#     - locale
#
# Adds:
#   * Lux::Locale module (the API; see ./load/locale.rb)
#   * Lux.locale            - shortcut accessor for Lux::Locale
#   * t(key, **opts)        - template helper, forwards to Lux.locale.t
#   * LuxTranslation model  - only when ApplicationModel is loaded; becomes
#                             the active Lux::Locale.store automatically

# Lux.locale shortcut
module ::Lux
  def locale = Lux::Locale
end

# Template helper: = t('users.welcome', name: @user.name)
# Bare t() returns the current (or default) locale.
module Lux::Template::Helper
  def t(key = nil, **opts) = Lux.locale.t(key, **opts)
end

# DB-backed store. Apps that don't have a DB (or just want the file backend)
# simply don't define ApplicationModel; the file backend stays active.
if defined?(ApplicationModel)
  require_relative 'lib/lux_translation'
  Lux::Locale.store = LuxTranslation
end
