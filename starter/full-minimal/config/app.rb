require_relative 'env'

# Load app files. The ./app autoloader hangs off Object.const_missing, which
# never fires for a constant looked up inside a module - UserSession resolving
# User is exactly that - so load them up front instead.
Dir.require_all './app', skip: '/assets/auto/'
