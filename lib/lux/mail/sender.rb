# Outbound mail: compose + render + deliver, wrapper over the `mail` gem.
# Canonical name is Lux::Mail::Sender; Lux::Mailer is kept as a back-compat
# alias (subclass either - `class Mailer < Lux::Mail::Sender`).
#
# sugessted usage
# Mailer.deliver(:email_login, 'foo@bar.baz')
# Mailer.render(:email_login, 'foo@bar.baz')
#
# natively works like
# Mailer.prepare(:email_login, 'foo@bar.baz').deliver
# Mailer.prepare(:email_login, 'foo@bar.baz').body
#
# Rails mode via method missing is suported
# Mailer.email_login('foo@bar.baz').deliver
# Mailer.email_login('foo@bar.baz').body
#
# if you want to cancel mail delivery - mail.to = false
module Lux
  module Mail
    class Sender
      include ClassCallbacks

      cattr :template_root, default: './app/views', class: true
      cattr :helper, class: true
      cattr :layout, default: 'mailer', class: true

      define_callback :before
      define_callback :after
      define_callback :on_deliver

      # default delivery logger; subclasses may add more on_deliver blocks
      on_deliver do |mail|
        Lux.logger.info "[#{self.class}.#{@_template} to #{mail.to}] #{mail.subject}"
      end

      attr_reader :mail

      class << self
        # Sender.prepare(:email_login, 'foo@bar.baz')
        def prepare template, *args
          obj = new
          obj.instance_variable_set :@_template, template
          obj.run_callback :before

          if args[0].is_hash?
            obj.send template, **args[0]
          else
            obj.send template, *args
          end

          obj.run_callback :after
          obj
        end

        def render method_name, *args
          send(method_name, *args).body
        end

        def method_missing method_sym, *args
          prepare(method_sym, *args)
        end
      end

      ###

      def initialize
        @mail = {}.to_lux_hash :subject, :body, :to, :cc, :from
      end

      def body
        data = @mail.body

        unless data
          helper = Lux::Template::Helper.new self, self.class.helper
          layout = Lux::Template.find_layout './app/views', self.class.layout
          data = Lux::Template.render helper, template: "#{cattr.template_root}/mailer/#{@_template}", layout: layout
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
          Lux.current.defer(m) { |mail| mail.deliver! }
        end
      end

      private

      def build_mail_object
        return if @mail.to.class == FalseClass

        raise "From in mailer not defined"    unless @mail.from
        raise "To in mailer not defined"      unless @mail.to
        raise "Subject in mailer not defined" unless @mail.subject

        # ::Mail is the gem; bare `Mail` here would resolve to Lux::Mail.
        m = ::Mail.new
        m[:from]         = @mail.from
        m[:to]           = @mail.to
        m[:subject]      = @mail.subject
        m[:body]         = body
        m[:content_type] = 'text/html; charset=UTF-8'

        run_callback :on_deliver, m

        m
      end
    end
  end

  # Back-compat: the class used to be Lux::Mailer. Existing app mailers
  # (`class Mailer < Lux::Mailer`) keep working through this alias.
  Mailer = Mail::Sender
end
