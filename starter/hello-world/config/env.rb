ENV['LUX_ENV'] ||= 'development'

require 'bundler/setup'
require 'lux-fw'

Lux.boot!
