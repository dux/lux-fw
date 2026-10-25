# Router helpers shared by web_common apps, callable from `Lux.router do ... end`
# route blocks. An app `def` with the same name inside Lux.router overrides one.

module WebCommonRoutes
  # /lux - server diagnostics (ServerInfo), dev or global admin only
  def server_info
    return unless nav.root == 'lux' && (Lux.env.dev? || user&.can&.admin?)

    render text: ServerInfo.report, content_type: :txt
  end
end

Lux::Router.include WebCommonRoutes
