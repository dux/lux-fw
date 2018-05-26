module MailerHelper
  extend self

  def mail
    @mail
  end

  def host
    App.host
  end
end