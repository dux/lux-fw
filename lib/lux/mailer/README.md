## Lux::Mailer - send mails

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

### Example

sugessted usage

```ruby
Mailer.deliver(:confirm_email, 'foo@bar.baz')
Mailer.render(:confirm_email, 'foo@bar.baz')
```

natively works like

```
Mailer.prepare(:confirm_email, 'foo@bar.baz').deliver
Mailer.prepare(:confirm_email, 'foo@bar.baz').body
```

Rails mode via method missing is suported

```
Mailer.confirm_email('foo@bar.baz').deliver
Mailer.confirm_email('foo@bar.baz').body
```

### Example code

```ruby
class Mailer < Lux::Mailer
  helper :mailer

  # before mail is sent
  after do
    mail.from = "#{App.name} <no-reply@#{Lux.config.host}>"
  end

  # raw define mail
  def raw to:, subject:, body:
    mail.subject = subject
    mail.to      = to

    @body = body.as_html
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

    @link    = "#{App.http_host}/profile/password?user_hash=#{Crypt.encrypt(email)}"
  end
end
```