# authcog - central-auth sign-in, on its own so an app can take auth without
# the rest of the web layer.
#
#   load/authcog_controller.rb - callback landing, exchanges a hash for a session
#   load/user_session.rb       - session identity, sso_action links, sudo overlay
#
# web_common depends on this plugin, so apps that list web_common keep both
# constants without listing authcog themselves.

# UserSession#api_key_cache_key hashes the API key; needed before the load sweep.
require 'digest'
