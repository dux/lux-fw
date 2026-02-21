# Default mail logging
Lux.config.on_mail_send do |mail|
  Lux.logger.info "[#{self.class}.#{@_template} to #{mail.to}] #{mail.subject}"
end
