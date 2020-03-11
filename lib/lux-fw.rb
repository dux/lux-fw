require 'awesome_print'
require 'as-duration'
require 'colorize'
require 'jwt'
require 'hamlit'
require 'hamlit/block'
require 'rack'
require 'sequel'
require 'pry'
require 'clean-hash'
require 'clean-annotations'
require 'clean-hash/pollute'

if File.exist?('./.env')
  require 'dotenv'
  Dotenv.load
end

require_relative './overload/object'
require_relative './loader'

# pollutes ApplicationHelper, need to load after Lux is loaded
require 'html-tag'
