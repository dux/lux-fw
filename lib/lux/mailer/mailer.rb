# sugessted usage
# Mailer.deliver(:email_login, 'foo@bar.baz')
# Mailer.render(:email_login, 'foo@bar.baz')

# natively works like
# Mailer.prepare(:email_login, 'foo@bar.baz').deliver
# Mailer.prepare(:email_login, 'foo@bar.baz').body

# Rails mode via method missing is suported
# Mailer.email_login('foo@bar.baz').deliver
# Mailer.email_login('foo@bar.baz').body

# if you want to cancel mail delivery - mail.to = false
module Lux
  class Mailer
    class_attribute :template_root, './app/views/mailer'

    define_callback :before
    define_callback :after

    class_attribute :helper
    class_attribute :layout, 'mailer'

    attr_reader :mail

    class << self
      # Mailer.prepare(:email_login, 'foo@bar.baz')
      def prepare template, *args
        obj = new
        obj.instance_variable_set :@_template, template
        obj.run_callback :before
        obj.send template, *args
        obj.run_callback :after
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
      @mail = {}.to_ch [:subject, :body, :to, :cc, :from]
    end

    def body
      data = @mail.body

      unless data
        helper = Lux::Template::Helper.new self, self.class.helper
        data = Lux::Template.render helper, template: "#{self.class.template_root}/mailer/#{@_template}", layout: "layouts/#{self.class.layout}"
      end

      data.gsub(%r{\shref=(['"])/}) { %[ href=#{$1}#{Lux.config.host}/] }
    end

    def subject
      @mail.subject
    end

    def to
      @mail.to
    end

    def deliver
      if m = build_mail_object
        Lux.delay(m) { |mail| mail.deliver! }
      end
    end

    private

    def build_mail_object
      return if @mail.to.class == FalseClass

      raise "From in mailer not defined"    unless @mail.from
      raise "To in mailer not defined"      unless @mail.to
      raise "Subject in mailer not defined" unless @mail.subject

      m = Mail.new
      m[:from]         = @mail.from
      m[:to]           = @mail.to
      m[:subject]      = @mail.subject
      m[:body]         = body
      m[:content_type] = 'text/html; charset=UTF-8'

      instance_exec m, &Lux.config.on_mail_send

      m
    end
  end
end