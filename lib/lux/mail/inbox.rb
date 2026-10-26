# Inbound mail. The mirror of Lux::Mail::Sender: a single `on_receive`
# callback that fires for every incoming message, from either transport:
#
#   * :post     - pushed by a webhook (e.g. a Cloudflare Email Worker), the
#                 app builds a Message from the parsed payload and calls
#                 Lux.mail_received(msg, :post).
#   * :mailbox  - pulled by `hammer mail:pull` from a configured IMAP inbox.
#
# Both normalize to a Message and run the same handlers. Register one:
#
#   Lux::Mail::Inbox.on_receive do |mail, type|
#     SupportTicket.intake(mail) if mail.verified
#   end
module Lux
  module Mail
    class Inbox
      include ClassCallbacks

      define_callback :on_receive

      # Normalized inbound message. `source` is :post or :mailbox.
      Message ||= Struct.new(
        :to, :from, :from_name, :subject, :text, :html,
        :message_id, :in_reply_to, :spf, :dkim, :dmarc,
        :headers, :raw, :source,
        keyword_init: true
      ) do
        # local part of the recipient ("sohotasks" from "sohotasks@support.x")
        def local  = to.to_s[/[^@]+/]
        def domain = to.to_s.split('@').last

        # DMARC alignment - the gate apps use before trusting `from`.
        def verified = dmarc.to_s.downcase == 'pass'
      end

      class << self
        # Fire the inbound event. `data` is a Message or a plain hash of the
        # fields above. Returns the Message that was dispatched.
        def receive(data, source)
          msg        = data.is_a?(Message) ? data : build_message(data)
          msg.source = source
          new.run_callback :on_receive, msg, source
          msg
        end

        # Pull unseen mail from every configured inbox and fire :mailbox events.
        # Config (config.yaml):
        #   mail:
        #     inboxes:
        #       - { host: imap.gmail.com, user: support@x, password: ..., folder: INBOX }
        def pull
          cfg     = Lux.config[:mail]
          inboxes = cfg && cfg[:inboxes]
          inboxes = [inboxes] if inboxes.is_hash?
          Array(inboxes).each { |inbox| pull_one(inbox.to_lux_hash) }
          nil
        end

        # Parse a raw RFC822 string into a Message. Handy for inbound webhooks
        # that forward the original MIME (e.g. a Cloudflare Email Worker posting
        # message.raw) rather than pre-parsed fields.
        def parse(raw)
          parse_rfc822 raw
        end

        private

        def build_message(data)
          h = data.to_lux_hash
          Message.new(
            to:          h[:to],
            from:        h[:from],
            from_name:   h[:from_name],
            subject:     h[:subject],
            text:        h[:text],
            html:        h[:html],
            message_id:  h[:message_id],
            in_reply_to: h[:in_reply_to],
            spf:         h[:spf],
            dkim:        h[:dkim],
            dmarc:       h[:dmarc],
            headers:     h[:headers],
            raw:         h[:raw],
          )
        end

        def pull_one(cfg)
          require 'net/imap'

          ssl  = cfg[:ssl].nil? ? true : cfg[:ssl]
          imap = Net::IMAP.new(cfg[:host], port: cfg[:port] || 993, ssl: ssl)
          imap.login cfg[:user], cfg[:password]
          imap.select(cfg[:folder] || 'INBOX')

          imap.search(['NOT', 'SEEN']).each do |seq|
            rfc822 = imap.fetch(seq, 'RFC822').first.attr['RFC822']
            begin
              receive parse_rfc822(rfc822), :mailbox
              imap.store(seq, '+FLAGS', [:Seen])   # processed; a raise leaves it unseen to retry
            rescue => error
              Lux.logger.error "[mail:pull] #{cfg[:user]} ##{seq}: #{error.message}"
            end
          end
        ensure
          if imap
            imap.logout rescue nil
            imap.disconnect rescue nil
          end
        end

        # Parse a raw RFC822 string (via the `mail` gem) into a Message.
        def parse_rfc822(raw)
          m = ::Mail.read_from_string(raw)
          Message.new(
            to:          m.to&.first,
            from:        m.from&.first,
            from_name:   (m[:from]&.display_names&.compact&.first),
            subject:     m.subject,
            text:        (m.multipart? ? m.text_part&.decoded : m.body&.decoded),
            html:        m.html_part&.decoded,
            message_id:  m.message_id,
            in_reply_to: Array(m.in_reply_to).first,
            spf:         auth_result(m, 'spf'),
            dkim:        auth_result(m, 'dkim'),
            dmarc:       auth_result(m, 'dmarc'),
            raw:         raw,
          )
        end

        # Pull a single mechanism verdict ("...; dmarc=pass ..." -> "pass") out of
        # an Authentication-Results header whose authserv-id (the token before the
        # first ";") is in config `mail.trusted_authserv_ids`. Senders can add their
        # own A-R headers, so untrusted ones are ignored; with no ids configured the
        # verdict is nil (and `verified` false).
        def auth_result(mail, method)
          trusted = Array(Lux.config.dig(:mail, :trusted_authserv_ids)).map { |id| id.to_s.downcase }
          return nil if trusted.empty?

          mail.header.fields.each do |field|
            next unless field.name.to_s.casecmp?('Authentication-Results')
            value = field.value.to_s
            next unless trusted.include?(value.split(';', 2).first.to_s.strip.split(/\s+/).first.to_s.downcase)
            verdict = value[/\b#{method}=(\w+)/i, 1] and return verdict
          end
          nil
        end
      end
    end
  end

  # Convenience: Lux.mail_received(mail, :post) / (mail, :mailbox)
  def mail_received(mail, type) = Lux::Mail::Inbox.receive(mail, type)
end
