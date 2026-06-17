# Cloudflare Email Service delivery for the `mail` gem.
#
# Plug into an app's Mail.defaults; secrets stay in the app:
#
#   Mail.defaults do
#     delivery_method Lux::Mail::CloudflareDelivery,
#       account_id: Lux.secrets.cloudflare.account_id,
#       api_token:  Lux.secrets.cloudflare.api_token
#   end
#
# Cloudflare Email Service is in public beta; the sending domain must be set
# up in Email Routing. The send path still varies across CF's docs - override
# :api_url if your dashboard shows a different one.
require 'net/http'
require 'json'

module Lux
  module Mail
    class CloudflareDelivery
      DEFAULT_API_URL ||= 'https://api.cloudflare.com/client/v4/accounts/%s/email/sending/send'

      def initialize(settings = {})
        @settings = settings
      end

      def deliver!(mail)
        account_id = @settings[:account_id] or raise 'CloudflareDelivery: missing :account_id'
        api_token  = @settings[:api_token]  or raise 'CloudflareDelivery: missing :api_token'

        uri = URI(@settings[:api_url] || (DEFAULT_API_URL % account_id))

        req = Net::HTTP::Post.new(uri)
        req['Authorization'] = "Bearer #{api_token}"
        req['Content-Type']  = 'application/json'
        req.body = build_body(mail).to_json

        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
        raise "CloudflareDelivery: send failed (#{res.code}) #{res.body}" unless res.is_a?(Net::HTTPSuccess)

        mail
      end

      private

      def build_body(mail)
        recipients = Array(mail.to)

        body = {
          from:    mail[:from].to_s,
          to:      recipients.one? ? recipients.first : recipients,
          subject: mail.subject,
        }

        if mail.multipart?
          body[:html] = mail.html_part&.decoded
          body[:text] = mail.text_part&.decoded
        elsif mail.content_type&.include?('text/plain')
          body[:text] = mail.body.decoded
        else
          body[:html] = mail.body.decoded
        end

        body[:cc]  = Array(mail.cc)  if mail.cc
        body[:bcc] = Array(mail.bcc) if mail.bcc

        body.compact
      end
    end
  end
end
