# Lux::Mailer - agent guide

Mailer subclassing `Lux::Mailer`. Method = template name. Templates at
`./app/views/mailer/<name>.(haml|erb)` inside `layout.(haml|erb)`.

## Canonical example

```ruby
class Mailer < Lux::Mailer
  helper :mailer

  after do
    mail.from = "#{App.name} <no-reply@#{Lux.config.host}>"
  end

  def lost_password user
    mail.subject = 'Password reset'
    mail.to      = user.email
    @link        = "#{App.http_host}/reset?t=#{Crypt.encrypt(user.id)}"
  end
end

Mailer.deliver(:lost_password, user)
```

## Rules

* **One method per email.** The method name maps to the template file.
* **Set `mail.subject` / `mail.to` / `mail.from`** inside the method.
* **Instance variables** in the method are visible in the template.
* **`before` / `after` callbacks** at the class level run around every
  delivery. Use `after` to set defaults like the from-address.
* **Three equivalent invocations** (real apps use all three):
  * `Mailer.deliver(:lost_password, user)` - symbol form
  * `Mailer.lost_password(user).deliver` - method-style (most common
    in real apps - reads like a normal Ruby method call)
  * `Mailer.prepare(:lost_password, user).deliver` - explicit prepare
* **Mailer methods accept any arg shape** the Ruby method signature
  allows - positional, keyword, mixed. Example:
  `def raw(to:, subject:, body:)` is called as
  `Mailer.raw(to: '...', subject: '...', body: '...').deliver`.
* **For async send**, wrap in `Lux.defer { Mailer.deliver(...) }`. The
  built-in `deliver` already dispatches through `Lux.defer`; only wrap
  manually when you want a different context arg.
* **For body-only** (preview / test), `Mailer.render(:name, *args)` or
  `Mailer.prepare(...).body`.
* **Logging hook:** `Lux.config.on_mail_send { |mail| ... }`. Use the
  named logger pattern (`Lux.logger(:email)`).

## Don't

* Build HTML strings in the method - use the template. The whole point.
* Forget the layout file - the framework wraps automatically; if there's
  no `layout.haml` your mail will render unlayouted.
* Send in the request thread without `Lux.defer` - mail servers are the
  slowest dependency.
* Use `Mail::Message` directly when you already have a Mailer subclass.

## See also

* [`Lux::Template` AGENTS](../template/AGENTS.md)
* [`Lux::Current` AGENTS](../current/AGENTS.md) - `Lux.defer`
