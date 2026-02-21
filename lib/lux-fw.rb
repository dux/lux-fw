require 'bundler/setup'
require 'dotenv'
Dotenv.load

require 'amazing_print'
require 'as-duration'
require 'json'
require 'jwt'
require 'haml'
require 'rack'
require 'sequel'
require 'pry'
require 'hash_wia'
require 'class-cattr'
require 'class-callbacks'

require_relative './overload/object'
require_relative './overload/string'
require_relative './loader'

# pollutes ApplicationHelper, need to load after Lux is loaded
require 'html-tag'
require 'view-cell'
