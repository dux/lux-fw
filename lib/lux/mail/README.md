# Lux::Mail

Mail in and out, wrapper over [`mail`](https://github.com/mikel/mail).

* `Lux::Mail::Sender` - compose + render + deliver outbound mail.
* `Lux::Mail::Inbox`  - one `on_receive` event for inbound mail, from a
  webhook push or an IMAP pull.

> `Lux::Mailer` is a back-compat alias for `Lux::Mail::Sender`, so existing
> `class Mailer < Lux::Mailer` mailers keep working unchanged.

> Inside `module Lux`, bare `Mail` resolves to `Lux::Mail`, **not** the gem.
> Use `::Mail` when you mean the gem (see `sender.rb#build_mail_object`).

## Sender (outbound)

Subclass `Lux::Mail::Sender`; each instance method is a mail definition.
`Sender.deliver(:method, *args)` is the canonical call; method-missing
style (`Sender.welcome(user).deliver`) is supported too.

```ruby
class Mailer < Lux::Mail::Sender
  helper :mailer

  after do
    mail.from = "#{App.name} <no-reply@#{Lux.config.host}>"
  end

  # raw, no template
  def raw to:, subject:, body:
    mail.subject = subject
    mail.to      = to
    mail.body    = body.as_html
  end

  # templated: renders ./app/views/mailer/lost_password.haml inside layout.haml
  def lost_password user
    mail.subject = "#{App.name} - reset link"
    mail.to      = user.email
    @user        = user
    @link        = "#{App.http_host}/reset?token=#{Lux.crypt.encrypt(user.id)}"
  end
end

Mailer.deliver(:lost_password, user)           # render + deliver
Mailer.render(:lost_password, user)            # render body String, no send
Mailer.prepare(:lost_password, user).deliver   # explicit prepare + deliver
Mailer.lost_password(user).deliver             # method_missing style

Lux.defer { Mailer.deliver(:welcome, user) }   # background thread
```

Templates live in `./app/views/mailer/<name>.haml` + `layout.haml`. A
class-level `on_deliver` block runs just before send with the built
`Mail::Message` (stackable; e.g. log every outgoing mail).

| call | returns | notes |
|------|---------|-------|
| `Sender.deliver(:method, *args)` | `Mail::Message` | render + send |
| `Sender.render(:method, *args)` | String | rendered body, no send |
| `Sender.prepare(:method, *args)` | instance | call `.deliver` or `.body` |
| `Sender.<method>(*args).deliver` | `Mail::Message` | method_missing style |

## Inbox (inbound)

A single event fires for every incoming message, regardless of how it
arrived. Register a handler once (e.g. in `config/init/`):

```ruby
Lux::Mail::Inbox.on_receive do |mail, type|
  # type is :post (webhook) or :mailbox (IMAP pull); mail.source is the same
  SupportTicket.intake(mail) if mail.verified
end
```

Handlers receive a `Lux::Mail::Inbox::Message`:

| field | note |
|-------|------|
| `to` `from` `from_name` `subject` `text` `html` | the message |
| `message_id` `in_reply_to` | threading |
| `spf` `dkim` `dmarc` | verdicts (from the transport / Authentication-Results) |
| `headers` `raw` `source` | extras; `source` is `:post` / `:mailbox` |
| `#local` `#domain` | recipient parts (`"a"` / `"b.com"` from `"a@b.com"`) |
| `#verified` | `dmarc == 'pass'` - the trust gate before auto-creating records |

### Transport 1 - push (`:post`)

A webhook builds a Message from the parsed payload and fires the event:

```ruby
# in an API/controller that a Cloudflare Email Worker POSTs to
Lux.mail_received(params, :post)   # params -> Message -> on_receive handlers
```

### Transport 2 - pull (`:mailbox`)

`hammer mail:pull` connects to each configured IMAP inbox, fetches UNSEEN
messages, fires the event per message, and marks each `\Seen` on success
(a raised handler leaves it unseen so the next run retries). Cron it.

```yaml
# config/config.yaml
mail:
  inboxes:
    - host: imap.gmail.com
      user: support@example.com
      password: <app-password>
      folder: INBOX        # optional, default INBOX
      port: 993            # optional, default 993
      ssl: true            # optional, default true
```

## Cloudflare transports

Both directions ship a Cloudflare adapter (Cloudflare Email Service, public
beta as of 2026).

### Send - `Lux::Mail::CloudflareDelivery`

A `mail`-gem delivery method; pick it per app, secrets stay in the app:

```ruby
Mail.defaults do
  delivery_method Lux::Mail::CloudflareDelivery,
    account_id: Lux.secrets.cloudflare.account_id,
    api_token:  Lux.secrets.cloudflare.api_token
end
```

POSTs a flat `{from, to, subject, html, text}` body to the CES REST API. The
send path is still beta - override `:api_url` if your dashboard differs.

### Receive - `Lux::Mail::CloudflareInbound`

Set up Email Routing -> a Worker that POSTs each message to an app route; that
route hands the payload to the adapter, which normalizes it (raw MIME or
postal-mime fields) and fires the shared `on_receive`:

```ruby
# config/init/ - register the handler once
Lux::Mail::Inbox.on_receive { |mail, _type| SupportTicket.intake(mail) if mail.verified }

# the route the Worker hits
Lux::Mail::CloudflareInbound.receive(params)
```

## See also

* [`./sender.rb`](./sender.rb) - outbound, `on_deliver` pre-delivery hook
* [`./inbox.rb`](./inbox.rb) - inbound event + IMAP pull
* [`./cloudflare_delivery.rb`](./cloudflare_delivery.rb) - CES REST send
* [`./cloudflare_inbound.rb`](./cloudflare_inbound.rb) - CF Email Worker webhook -> Inbox
* [`../../../bin/cli/mail_hammer.rb`](../../../bin/cli/mail_hammer.rb) - `mail:pull`
* [`../template/README.md`](../template/README.md) - the rendering engine
