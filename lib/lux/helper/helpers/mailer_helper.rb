module MailerHelper
  extend self

  def mail
    @mail
  end

  def host
    ENV.fetch('HOST')
  end
end