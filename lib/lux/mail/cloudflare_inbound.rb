# Cloudflare inbound mail adapter. A Cloudflare Email Worker (Email Routing ->
# Worker) POSTs each incoming message to your app; this normalizes that payload
# into a Lux::Mail::Inbox::Message and fires the shared on_receive event.
#
# Register the business handler once (e.g. in config/init/), then call this
# from the webhook route the Worker hits:
#
#   Lux::Mail::Inbox.on_receive do |mail, type|
#     SupportTicket.intake(mail) if mail.verified
#   end
#
#   # in the inbound route/controller
#   Lux::Mail::CloudflareInbound.receive(params)
#
# The Worker may POST either the raw MIME (key :raw, parsed here in full) or
# pre-parsed fields (postal-mime style: from/to as strings or {address,name}).
module Lux
  module Mail
    class CloudflareInbound
      class << self
        # payload: a Hash (or params) from the Email Worker. Returns the
        # dispatched Lux::Mail::Inbox::Message.
        def receive(payload)
          data = payload.to_lux_hash
          msg  = data[:raw].to_s.empty? ? build_from_fields(data) : Inbox.parse(data[:raw])

          # explicit verdicts from the Worker win when the parsed MIME lacks them
          msg.spf   ||= data[:spf]
          msg.dkim  ||= data[:dkim]
          msg.dmarc ||= data[:dmarc]

          Inbox.receive msg, :post
        end

        private

        def build_from_fields(data)
          from = data[:from]

          Inbox::Message.new(
            to:          address(data[:to]),
            from:        address(from),
            from_name:   display_name(from) || data[:from_name],
            subject:     data[:subject],
            text:        data[:text] || data[:plain],
            html:        data[:html],
            message_id:  data[:message_id] || data[:messageId],
            in_reply_to: data[:in_reply_to] || data[:inReplyTo],
            spf:         data[:spf],
            dkim:        data[:dkim],
            dmarc:       data[:dmarc],
            headers:     data[:headers],
            raw:         data[:raw],
          )
        end

        # accept "a@b.com", "Name <a@b.com>", {address|email|value: ...}, or an
        # array of any of those (first recipient wins, matching Inbox's model)
        def address(val)
          case val
          when nil    then nil
          when String then val
          when Array  then address(val.first)
          when Hash
            h = val.to_lux_hash
            h[:address] || h[:email] || h[:value]
          else val.to_s
          end
        end

        def display_name(val)
          return unless val.is_a?(Hash)
          h = val.to_lux_hash
          h[:name] || h[:display_name]
        end
      end
    end
  end
end
