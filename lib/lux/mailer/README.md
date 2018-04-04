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

```
Mailer.deliver(:confirm_email, 'rejotl@gmailcom')
Mailer.render(:confirm_email, 'rejotl@gmailcom')
```

natively works like

```
Mailer.prepare(:confirm_email, 'rejotl@gmailcom').deliver
Mailer.prepare(:confirm_email, 'rejotl@gmailcom').body
```

Rails mode via method missing is suported

```
Mailer.confirm_email('rejotl@gmailcom').deliver
Mailer.confirm_email('rejotl@gmailcom').body
```
