# Router helpers shared by web_common apps, callable from `Lux.app do ... end`
# route blocks. An app `def` with the same name inside Lux.app overrides one.

module WebCommonRoutes
  # /lux - server diagnostics (ServerInfo), dev or global admin only
  def server_info
    return unless nav.root == 'lux' && (Lux.env.dev? || user&.can&.admin?)

    body ServerInfo.report, content_type: :txt
  end
end

Lux::Application.include WebCommonRoutes
