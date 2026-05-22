# Lux::Mailer

Mail composition + template rendering, wrapper over [`mail`](https://github.com/mikel/mail).

Subclass `Lux::Mailer`; each instance method is a mail definition.
`Mailer.deliver(:method, *args)` is the canonical call; method-missing
style (`Mailer.welcome(user).deliver`) is supported too.

## Full example

```ruby
class Mailer < Lux::Mailer
  helper :mailer

  before do
    # run before rendering starts (set up shared instance vars, log, ...)
  end

  after do
    # run after rendering, before delivery (set from address, headers, ...)
    mail.from = "#{App.name} <no-reply@#{Lux.config.host}>"
    mail.headers['x-app'] = App.name
  end

  # --- raw, no template -----------------------------------------------
  def raw to:, subject:, body:
    mail.subject = subject
    mail.to      = to
    mail.body    = body.as_html
  end

  # --- templated mail --------------------------------------------------
  # renders ./app/views/mailer/lost_password.haml inside layout.haml
  def lost_password user
    mail.subject = "#{App.name} - reset link"
    mail.to      = user.email
    @user        = user
    @link        = "#{App.http_host}/reset?token=#{Lux.crypt.encrypt(user.id)}"
  end
end

# --- ways to send / inspect ------------------------------------------

Mailer.deliver(:lost_password, user)           # render + deliver
Mailer.render(:lost_password, user)            # render body, return String, do not send
Mailer.prepare(:lost_password, user).deliver   # explicit prepare + deliver
Mailer.prepare(:lost_password, user).body      # body without sending
Mailer.lost_password(user).deliver             # method_missing style

# --- async send -----------------------------------------------------

Lux.defer { Mailer.deliver(:welcome, user) }   # background thread

# --- mail send hook (e.g. log every outgoing) -----------------------

Lux.config.on_mail_send do |mail|
  Lux.logger(:email).info "[#{self.class}.#{@_template} to #{mail.to}] #{mail.subject}"
end
```

## Templates

`./app/views/mailer/<name>.haml` (or `.erb`) + `./app/views/mailer/layout.haml`.
Instance variables set in the mailer method are visible in the template.

`Mailer.deliver(:welcome, user)` does:

1. instantiate `Mailer`, call `welcome(user)` → sets up `mail.*`
2. render `./app/views/mailer/welcome.haml`
3. wrap in `./app/views/mailer/layout.haml`
4. deliver

## API

| call | returns | notes |
|------|---------|-------|
| `Mailer.deliver(:method, *args)` | `Mail::Message` | render + send |
| `Mailer.render(:method, *args)` | String | rendered body, no send |
| `Mailer.prepare(:method, *args)` | instance | call `.deliver` or `.body` |
| `Mailer.<method>(*args).deliver` | `Mail::Message` | method_missing style |

## See also

* [`../template/README.md`](../template/README.md) - the rendering engine
* [`../current/README.md`](../current/README.md) - `Lux.defer { Mailer.deliver(...) }` for async send
* [`../config/README.md`](../config/README.md) - `Lux.config.on_mail_send` hook
* [`AGENTS.md`](./AGENTS.md) - LLM guide
