require_relative 'environment'

###

Lux.config.secret     = 'secret'
Lux.config.host       = 'http://localhost:3000'

###

Lux.require_all './app'

###

Lux.start
