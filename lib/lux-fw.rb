require 'awesome_print'
require 'as-duration'
require 'colorize'
require 'jwt'
require 'hamlit'
require 'hamlit/block'
require 'hashie'
require 'rack'
require 'sequel'

require_relative './overload/object'

Encoding.default_internal = Encoding.default_external = 'utf-8'

Sequel.extension :inflector, :string_date_time
Sequel::Model.plugin :after_initialize
Sequel::Model.plugin :def_dataset_method
# Sequel::Model.plugin :hook_class_methods

Sequel.database_timezone = :utc
Sequel.default_timezone  = +2

# load basic lux libs
require_relative './lux/lux'

# load all lux libs
[:overload, :common, :vendor, :lux].each do |f|
  Lux::Config.require_all Lux.fw_root.join('./lib/%s' % f)
end

# load Tilt parsers
Tilt.register Tilt::ERBTemplate,       'erb'
Tilt.register Hamlit::Block::Template, 'haml'

# ensure we are not loading lux in lux folder
if Lux.root != Lux.fw_root
  # create folders if needed
  ['./log', './tmp'].each { |d| `mkdir #{d}` unless Dir.exist?(d) }
end

