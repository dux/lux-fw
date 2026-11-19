# Lux::Mail

Outbound mail, wrapper over [`mail`](https://github.com/mikel/mail).

* `Lux::Mail::Sender` - compose + render + deliver outbound mail.

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

  # templated: renders ./app/views/mailer/lost_password.haml inside the mailer layout
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

Templates live in `./app/views/mailer/<name>.haml`; the layout is `./app/views/layouts/mailer.*` or `./app/views/mailer/layout.*` (`layout` cattr, default `'mailer'`).
A class-level `on_deliver` block runs just before send with the built
`Mail::Message` (stackable; e.g. log every outgoing mail).

| call | returns | notes |
|------|---------|-------|
| `Sender.deliver(:method, *args)` | `Mail::Message` (nil if `mail.to = false`) | render + send |
| `Sender.render(:method, *args)` | String | rendered body, no send |
| `Sender.prepare(:method, *args)` | instance | call `.deliver` or `.body` |
| `Sender.<method>(*args).deliver` | `Mail::Message` | method_missing style |

## Send through Cloudflare - `Lux::Mail::CloudflareDelivery`

Cloudflare Email Service, public beta as of 2026.

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

## See also

* [`./sender.rb`](./sender.rb) - outbound, `on_deliver` pre-delivery hook
* [`./cloudflare_delivery.rb`](./cloudflare_delivery.rb) - CES REST send
* [`../template/README.md`](../template/README.md) - the rendering engine
