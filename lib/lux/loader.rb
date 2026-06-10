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
require 'class-callbacks'

Pry.config.input = Reline

# Give text/web extensions Rack has no mapping for a sane type, otherwise they
# fall back to application/octet-stream and browsers download them.
Rack::Mime::MIME_TYPES['.md']          ||= 'text/plain'
Rack::Mime::MIME_TYPES['.fez']         ||= 'text/plain'
Rack::Mime::MIME_TYPES['.cjs']         ||= 'text/javascript'
Rack::Mime::MIME_TYPES['.map']         ||= 'application/json'
Rack::Mime::MIME_TYPES['.webmanifest'] ||= 'application/manifest+json'

# Overloads required ahead of Lux core so const_missing autoloader (object.rb)
# and core String/Dir helpers exist before lux/lux.rb runs.
require_relative '../overload/object'
require_relative '../overload/string'
require_relative '../overload/dir'

# Defines Lux module (root, fw_root, VERSION, UNSET, speed, app_caller).
require_relative './lux'
require_relative './hash/hash'

# Class attributes (`cattr` macro), vendored from class-cattr. Patches
# Class/Object, so load it before Controller/Mailer/ViewCell call `cattr`.
require_relative './utils/class_attributes'

# Subsystems required ahead of the Dir.require_all sweep below because boot
# code (Lux.dotenv, Lux.config, Lux.shell.info) calls them directly.
require_relative './shell/error'
require_relative './shell/shell'
require_relative './shell/lux_adapter'

require_relative './environment/environment'
require_relative './environment/mode'
require_relative './environment/runtime'
require_relative './environment/lux_adapter'

require_relative './logger/lux_adapter'

require_relative './boot/config/config'
require_relative './boot/config/lux_adapter'

# HtmlTag is vendored under Lux::Utils::HtmlTag. Pre-required because
# Dir.require_all (below) sorts shallowest-first, so view_cell.rb at depth
# 2 would otherwise hit `include HtmlTag` before the depth-3 html_tag/
# files load.
require_relative './utils/html_tag/html_tag'
require_relative './utils/html_tag/inbound'
require_relative './utils/html_tag/globals'

require_relative './boot/boot'
require_relative './boot/lux_adapter'

Sequel.extension     :inflector
Sequel::Model.plugin :after_initialize
Sequel::Model.plugin :def_dataset_method

Sequel.database_timezone = :utc
# Sequel.default_timezone  = +2

# ensure we are not loading lux in lux folder
if Lux.root != Lux.fw_root
  # create folders if needed
  ['./log', './tmp'].each { |d| Dir.mkdir(d) unless Dir.exist?(d) }
end

# load all lux libs (lib/lux/test/ stays out — test scaffolding is opt-in
# via spec_helper so production apps don't pull in minitest)
[:overload, :lux].each do |f|
  opts = f == :lux ? { skip: '/lux/test/' } : {}
  Dir.require_all Lux.fw_root.join('./lib/%s' % f), opts
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

  inflect.irregular 'bonus', 'bonuses'
  inflect.uncountable 'data'
  inflect.uncountable 'media'
  inflect.irregular 'criterion', 'criteria'
  inflect.irregular 'axis', 'axes'
  inflect.irregular 'leaf', 'leaves'
  inflect.irregular 'focus', 'focuses'
end

# load Tilt parsers
Haml::Template.options[:escape_html] = false
# Tilt.register Tilt::ERBTemplate, 'erb'
# Tilt.register Haml::Template, 'haml'

# App-side boot (env, dotenv, Bundler.require, config.yaml, plugin
# loaders) is driven by Lux.boot!. The host's config/env.rb must call
# it - optionally with a block for pre-plugin config overrides:
#
#   Lux.boot! do
#     Lux.config.localize = false
#   end
#
# `bin/lux` invokes Lux.boot! from its :env / :app tasks; light CLI
# commands (`lux mount`, `lux --help`) skip it and stay fast.
