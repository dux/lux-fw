# Lux.plugin :authcog

Central-auth landing controller. Browser is redirected to
`/authcog?callback=<40-char-hash>` after a successful login at the central
auth host configured in `Lux.config.authcog`. This plugin exchanges the hash
for `{ email, name, avatar, provider }` and signs the user in.

## Setup

```ruby
Lux.plugin :authcog
```

Wire up in `routes.rb`:

```ruby
map 'authcog', 'authcog#call'
```

## Layout

```
plugins/authcog/
  loader.rb                  # requires lib/authcog_controller
  lib/
    authcog_controller.rb
```
