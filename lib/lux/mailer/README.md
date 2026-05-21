# Lux::Mailer

Mail composition + template rendering, wrapper over [`mail`](https://github.com/mikel/mail).

## Small example

```ruby
class Mailer < Lux::Mailer
  def welcome user
    mail.subject = 'Welcome'
    mail.to      = user.email
    @user = user                # available in template
  end
end

Mailer.deliver(:welcome, user)
```

`Mailer.deliver(:welcome, user)` does:

1. instantiate `Mailer`, call `welcome(user)` → set up `mail.*`
2. render `./app/views/mailer/welcome.haml` (instance vars available)
3. wrap in `./app/views/mailer/layout.haml`
4. deliver

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

  # ---- raw, no template ----
  def raw to:, subject:, body:
    mail.subject = subject
    mail.to      = to
    mail.body    = body.as_html
  end

  # ---- templated mail ----
  # renders ./app/views/mailer/lost_password.haml inside layout.haml
  def lost_password user
    mail.subject = "#{App.name} – reset link"
    mail.to      = user.email
    @link        = "#{App.http_host}/reset?token=#{Crypt.encrypt(user.id)}"
  end
end

# --- ways to call ----------------------------------------------------

Mailer.deliver(:lost_password, user)               # render + deliver
Mailer.render(:lost_password, user)                # render body, return string
Mailer.prepare(:lost_password, user).deliver       # explicit prepare
Mailer.prepare(:lost_password, user).body          # body without delivery
Mailer.lost_password(user).deliver                 # method_missing style

# --- mail logging ----------------------------------------------------

Lux.config.on_mail_send do |mail|
  Lux.logger(:email).info "[#{self.class}.#{@_template} to #{mail.to}] #{mail.subject}"
end
```

## Templates

`./app/views/mailer/<name>.haml` (or .erb) + `./app/views/mailer/layout.haml`.
Instance variables set in the mailer method are visible in the template.

## See also

* [`../template/README.md`](../template/README.md) - the rendering engine
* [`../current/README.md`](../current/README.md) - `Lux.defer { Mailer.deliver(...) }` for async send
* [`AGENTS.md`](./AGENTS.md) - LLM guide
