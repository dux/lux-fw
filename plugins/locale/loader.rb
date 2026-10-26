# Lux::Locale - namespaced flat-file translation lookup, with an optional
# opt-in DB-backed store (LuxTranslation, see README "DB-backed store").
#
# Enable in config.yaml:
#   plugins:
#     - locale
#
# Adds:
#   * Lux::Locale module (the API; see ./load/locale.rb)
#   * Lux.locale            - shortcut accessor for Lux::Locale
#   * t(key, **opts)        - template helper, forwards to Lux.locale.t
#   * lib/lux_translation.rb - LuxTranslation model; not loaded here, an app
#                             opts in with `Lux.locale.store = LuxTranslation`

# Lux.locale shortcut
module ::Lux
  def locale = Lux::Locale
end

# Current-thread shortcut: Lux.ctx.lpath('/service') / Lux.ctx.lpath(@user)
class ::Lux::Context
  def lpath(value = '/', **opts) = Lux.locale.path(value, **opts)
end

# Template helper: = t('users.welcome', name: @user.name)
# Bare t() returns the current (or default) locale.
module Lux::Template::Helper
  def t(key = nil, **opts) = Lux.locale.t(key, **opts)
  def lpath(value = '/', **opts) = Lux.locale.path(value, **opts)
end
