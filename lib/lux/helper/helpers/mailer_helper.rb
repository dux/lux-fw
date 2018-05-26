module MailerHelper
  extend self

  def mail
    @mail
  end

  def host
    Lux.config.host
  end
end