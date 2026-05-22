Encoding.default_internal = Encoding.default_external = 'utf-8'

# External runtime deps. Kept here (not in lib/lux-fw.rb) so the gem entry
# stays trivial and boot order lives in one file.
require 'amazing_print'
require 'as-duration'
require 'json'
require 'jwt'
require 'haml'
require 'rack'
require 'sequel'
require 'pry'
require 'reline'
require 'class-cattr'
require 'class-callbacks'
require 'html-tag'

Pry.config.input = Reline

# Overloads required ahead of Lux core so const_missing autoloader (object.rb)
# and core String/Dir helpers exist before lux/lux.rb runs.
require_relative '../overload/object'
require_relative '../overload/string'
require_relative '../overload/dir'

# Defines Lux module, Lux.env, Lux.config and friends.
require_relative './lux'
require_relative './hash/hash'

# Load .env files (.env.<env>.local, .env.local, .env.<env>, .env) before
# env-driven config / Lux.env resolution.
Lux.dotenv

Lux.init_env

# eager-load config.yaml so values are available to the rest of boot
Lux.config

Sequel.extension     :inflector
Sequel::Model.plugin :after_initialize
Sequel::Model.plugin :def_dataset_method

Sequel.database_timezone = :utc
# Sequel.default_timezone  = +2

Lux::Config.set_defaults

# ensure we are not loading lux in lux folder
if Lux.root != Lux.fw_root
  # create folders if needed
  ['./log', './tmp'].each { |d| Dir.mkdir(d) unless Dir.exist?(d) }
end

# load all lux libs
[:overload, :common, :lux].each do |f|
  Dir.require_all Lux.fw_root.join('./lib/%s' % f)
end

Sequel.inflections do |inflect|
  # inflect.plural /^(ox)$/i, '\1\2en'
  # inflect.singular /^(ox)en/i, '\1'
  # inflect.irregular 'octopus', 'octopi'
  inflect.plural   'bonus', 'bonuses'
  inflect.plural   'status', 'statuses'
  inflect.plural   'clothing', 'clothes'
  # inflect.plural   'person', 'people'
  inflect.singular /Data$/i, 'Data'
  inflect.uncountable 'news'
end

# String and Sequel have separate inflection stores.
# String#singularize uses String::Inflections, not Sequel::Inflections.
String.inflections do |inflect|
  inflect.singular /(status)$/i, '\1'
  inflect.singular /(bonus)$/i, '\1'
end

# load Tilt parsers
Haml::Template.options[:escape_html] = false
# Tilt.register Tilt::ERBTemplate, 'erb'
# Tilt.register Haml::Template, 'haml'

# auto-load configured plugins (from Lux.config[:plugins])
plugins = Lux::Plugin.normalize_names(Lux.config[:plugins])
if plugins.any?
  Lux.plugin(*plugins)
  Lux.shell.info "Lux plugins: #{plugins.join(', ')}"
else
  Lux.shell.info 'Lux: no plugins'
end
