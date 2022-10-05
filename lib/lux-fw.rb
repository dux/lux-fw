require 'amazing_print'
require 'as-duration'
require 'colorize'
require 'json'
require 'jwt'
require 'hamlit'
require 'rack'
require 'sequel'
require 'pry'
require 'hash_wia'
# require 'clean-annotations'
require 'class-cattr'
require 'class-callbacks'


require_relative './overload/object'
require_relative './loader'

# pollutes ApplicationHelper, need to load after Lux is loaded
require 'html-tag'
require 'view-cell'
