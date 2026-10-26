# Router helpers shared by web_common apps, callable from `Lux.router do ... end`
# route blocks. An app `def` with the same name inside Lux.router overrides one.

module WebCommonRoutes
  # /lux - server diagnostics (ServerInfo), dev or global admin only
  def server_info
    map 'lux' do
      raise Lux.error.not_found unless Lux.env.dev? || user&.can&.admin?
      render text: ServerInfo.report, content_type: :txt
    end
  end
end

Lux::Router.include WebCommonRoutes
