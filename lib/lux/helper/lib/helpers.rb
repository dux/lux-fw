module MailerHelper
  extend self

  def mail
    @mail
  end

  def host
    Lux.config.host
  end
end

module ApplicationHelper
end

module HtmlHelper
end