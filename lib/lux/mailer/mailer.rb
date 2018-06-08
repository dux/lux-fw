# sugessted usage
# Mailer.deliver(:confirm_email, 'rejotl@gmailcom')
# Mailer.render(:confirm_email, 'rejotl@gmailcom')

# natively works like
# Mailer.prepare(:confirm_email, 'rejotl@gmailcom').deliver
# Mailer.prepare(:confirm_email, 'rejotl@gmailcom').body

# Rails mode via method missing is suported
# Mailer.confirm_email('rejotl@gmailcom').deliver
# Mailer.confirm_email('rejotl@gmailcom').body

class Lux::Mailer
  class_callbacks :before, :after

  class_attribute :helper
  class_attribute :layout, 'mailer'

  attr_reader :mail

  class << self
    # Mailer.prepare(:confirm_email, 'rejotl@gmailcom')
    def prepare template, *args
      obj = new
      obj.instance_variable_set :@_template, template
      obj.class_callback :before
      obj.send template, *args
      obj.class_callback :after
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
    @mail = DynamicClass.new subject: nil, body: nil, to: nil, cc: nil, from: nil
  end

  def deliver
    raise "From in mailer not defined"    unless @mail.from
    raise "To in mailer not defined"      unless @mail.to
    raise "Subject in mailer not defined" unless @mail.subject

    require 'mail'

    Mail.defaults { delivery_method Lux.config(:mail).delivery, Lux.config(:mail).opts }

    m = Mail.new
    m[:from]         = @mail.from
    m[:to]           = @mail.to
    m[:subject]      = @mail.subject
    m[:body]         = @mail.body || body
    m[:content_type] = 'text/html; charset=UTF-8'

    Thread.new { m.deliver! }
  end

  def deliver_later
     Lux.delay self, :deliver
  end

  def body
    return @mail.body if @mail.body

    helper = Lux::Helper.new self, self.class.helper

    Lux::Template.render_with_layout "layouts/#{self.class.layout}", "mailer/#{@_template}", helper
  end

  def subject
    @mail.subject
  end

  def to
    @mail.to
  end

end