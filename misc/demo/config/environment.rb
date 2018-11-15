require 'bundler/setup'
require 'dotenv'

Dotenv.load

Bundler.require :default, ENV.fetch('RACK_ENV')

