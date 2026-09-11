require_relative 'env'

# Load app files up front. The resolver walks every app root, so files shipped
# by plugins in mount/ are loaded alongside ./app.
Lux.root.require_all 'app', skip: '/assets/auto/'
