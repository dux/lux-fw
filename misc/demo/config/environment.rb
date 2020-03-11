require 'bundler/setup'

Bundler.require :default, ENV.fetch('RACK_ENV')

# load app config
Dir.require_all './config/initializers'
