## Lux.current.response (Lux::Response)

Current request response object

You can allways use `Lux.current.response` object, or accesss it as `response` inside the controller.

```ruby
# add response header
response.header 'x-blah', 123

# max age of the page in seconds, default 0
response.max_age = 10

# the default access type is private
response.public = true

# page status
response.status = 400

# HTTP early hints
response.early_hints link, type

# generate etag header and stop response if matching header found
response.etag *args

# halt response render and deliver page
response.halt status, body

# set or get the body
# if you set the body, response is halted
response.body = @data # set body
response.body         # @body
response.body?        # true if body present

# get or set content type
response.content_type = :js
response.content_type = :plain
response.content_type

# send flash message to current request or to the next if redirect happens
response.flash 'Bad user name or pass'
response.flash.error 'Bad user name or pass'
response.flash.info 'Login ok'

# send file to a browser
response.send_file './tmp/local/location.pdf', inline: true

# redirect the request
response.redirect_to '/foo'
response.redirect_to :back, error: 'Bad user name or pass'

# basic http auth
response.auth do |user, pass|
  [user, pass] == ['foo', 'bar']
end
```

