# Lux.plugin :oauth

Interface to various oauth providers.

Supported: facebook, github, google, linkedin, slack, stackexchange, yahoo.

## Setup

```ruby
Lux.plugin :oauth
```

## Usage

```ruby
url   = LuxOauth.login(:facebook)         # build authorization URL
user  = LuxOauth.get(:facebook).callback  # exchange code for user data
```

## Layout

```
plugins/oauth/
  load/
    oauth.rb                 # LuxOauth base class
    providers/
      facebook.rb
      github.rb
      google.rb
      linkedin.rb
      slack.rb
      stackexchange.rb
      yahoo.rb
```
