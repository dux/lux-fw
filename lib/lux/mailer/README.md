## Lux::Mailer

Light wrapper arrond [ruby mailer gem](https://github.com/mikel/mail).

* before and after class methods are supported
  * before is called mail rendering started
  * after is called after rendering but just before mail is send
* similar as in rails, renders mail as any other template
  * based on ruby mail gem
    * mail_object.deliver will deliver email
    * mail_object.body will show mail body
    * mail_object.render will retrun mail object
* Mailer.forgot_password(email).deliver will
  * execute before filter
  * create mail object in Mailer class and call forgot_password method
  * render template app/views/mailer/forgot_password
  * render layout tempplate app/views/mailer/layout
  * execute after filter
  * deliver the mail

#### Example

sugessted usage

```ruby
Mailer.deliver(:email_login, 'foo@bar.baz')
Mailer.render(:email_login, 'foo@bar.baz')
```

natively works like

```
Mailer.prepare(:email_login, 'foo@bar.baz').deliver
Mailer.prepare(:email_login, 'foo@bar.baz').body
```

Rails mode via method missing is suported

```
Mailer.email_login('foo@bar.baz').deliver
Mailer.email_login('foo@bar.baz').body
```

#### Code

```ruby
class Mailer < Lux::Mailer
  helper :mailer

  # before method call
  before do
  end

  # after method call, but before mail is sent
  after do
    mail.from = "#{App.name} <no-reply@#{Lux.config.host}>"
  end

  # raw define mail
  def raw to:, subject:, body:
    mail.subject = subject
    mail.to      = to
    mail.body    = body.as_html
  end

  # send mail as
  #   Mailer.lost_password('foo@bar.baz').deliver
  #
  # renders tamplate and layout
  #   ./app/views/mailer/lost_password.haml
  #   ./app/views/mailer/layout.haml
  def lost_password email
    mail.subject = "#{App.name} – potvrda registracije"
    mail.to      = email

    # instance variables will be pased to templaes
    @link = "#{App.http_host}/profile/password?user_hash=#{Crypt.encrypt(email)}"
  end
end
```