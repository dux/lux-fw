# sugessted usage
# Mailer.deliver(:email_login, 'foo@bar.baz')
# Mailer.render(:email_login, 'foo@bar.baz')

# natively works like
# Mailer.prepare(:email_login, 'foo@bar.baz').deliver
# Mailer.prepare(:email_login, 'foo@bar.baz').body

# Rails mode via method missing is suported
# Mailer.email_login('foo@bar.baz').deliver
# Mailer.email_login('foo@bar.baz').body

class Lux::Mailer
  class_attribute :template_root, './app/views/mailer'

  class_callback :before
  class_callback :after

  class_attribute :helper
  class_attribute :layout, 'mailer'

  attr_reader :mail

  class << self
    # Mailer.prepare(:email_login, 'foo@bar.baz')
    def prepare template, *args
      obj = new
      obj.instance_variable_set :@_template, template
      Object.class_callback :before, obj
      obj.send template, *args
      Object.class_callback :after, obj
      obj
    end

    def render method_name, *args
      send(method_name, *args).body
    end

    def method_missing method_sym, *args
      prepare(method_sym, *args)
    end

    def deliver
      send(method_name, *args).deliver
    end
  end

  ###

  def initialize
    @mail = FreeStruct.new subject: nil, body: nil, to: nil, cc: nil, from: nil
  end

  def deliver
    m = build_mail_object
    self.delay.deliver_now
    # Lux.delay(m) { |mail| mail.deliver! }
  end

  def deliver_now
    m = build_mail_object
    m.deliver!
  end

  def body
    data = @mail.body

    unless data
      helper = Lux::View::Helper.new self, self.class.helper
      data = Lux::View.render_with_layout "layouts/#{self.class.layout}", "#{self.class.template_root}/mailer/#{@_template}", helper
    end

    data.gsub(%r{\shref=(['"])/}) { %[ href=#{$1}#{Lux.config.host}/] }
  end

  def subject
    @mail.subject
  end

  def to
    @mail.to
  end

  private

  def build_mail_object
    raise "From in mailer not defined"    unless @mail.from
    raise "To in mailer not defined"      unless @mail.to
    raise "Subject in mailer not defined" unless @mail.subject

    m = Mail.new
    m[:from]         = @mail.from
    m[:to]           = @mail.to
    m[:subject]      = @mail.subject
    m[:body]         = body
    m[:content_type] = 'text/html; charset=UTF-8'

    instance_exec m, &Lux.config.on_mail

    m
  end

end