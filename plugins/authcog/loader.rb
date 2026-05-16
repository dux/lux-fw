# Authcog - central-auth landing controller.
#
# Browser is redirected to /authcog?callback=<40-char-hash> after a successful
# login at the central auth host configured in Lux.config.authcog. This plugin
# exchanges the hash for { email, name, avatar, provider } and signs the user in.
#
# Wire up in routes.rb:
#   map 'authcog', 'authcog#call'

require_relative 'lib/authcog_controller'
