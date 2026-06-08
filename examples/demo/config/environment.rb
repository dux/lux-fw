require 'bundler/setup'

Bundler.require :default, ENV.fetch('LUX_ENV', 'development')

# load app config
Dir.require_all './config/initializers'
