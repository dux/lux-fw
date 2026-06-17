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
      Message = Struct.new(
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
          Array(inboxes).each { |inbox| pull_one(inbox) }
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
          (imap.logout rescue nil) && (imap.disconnect rescue nil) if imap
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

        # Pull a single mechanism verdict out of the Authentication-Results
        # header ("...; dmarc=pass ..." -> "pass"), nil if absent.
        def auth_result(mail, method)
          line = mail['Authentication-Results']&.to_s or return nil
          line[/\b#{method}=(\w+)/i, 1]
        end
      end
    end
  end

  # Convenience: Lux.mail_received(mail, :post) / (mail, :mailbox)
  def mail_received(mail, type) = Lux::Mail::Inbox.receive(mail, type)
end
