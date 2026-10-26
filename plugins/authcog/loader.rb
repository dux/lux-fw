# authcog - central-auth sign-in, on its own so an app can take auth without
# the rest of the web layer.
#
#   load/authcog_router.rb - callback landing, exchanges a hash for a session
#   load/user_session.rb       - session identity, sso_action links, sudo overlay
#
# Independent of web_common; an app lists authcog itself (next to web_common if it has it).

# UserSession#api_key_cache_key hashes the API key; needed before the load sweep.
require 'digest'
