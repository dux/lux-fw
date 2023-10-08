Encoding.default_internal = Encoding.default_external = 'utf-8'

Sequel.extension     :inflector
Sequel::Model.plugin :after_initialize
Sequel::Model.plugin :def_dataset_method

Sequel.database_timezone = :utc
# Sequel.default_timezone  = +2

# load basic lux libs
require_relative './overload/dir'
require_relative './lux/lux'

Lux::Config.set_defaults

# load all lux libs
[:overload, :common, :lux].each do |f|
  Dir.require_all Lux.fw_root.join('./lib/%s' % f)
end

# load Tilt parsers
Haml::Template.options[:escape_html] = false
# Tilt.register Tilt::ERBTemplate, 'erb'
# Tilt.register Haml::Template, 'haml'

# ensure we are not loading lux in lux folder
if Lux.root != Lux.fw_root
  # create folders if needed
  ['./log', './tmp'].each { |d| `mkdir #{d}` unless Dir.exist?(d) }
end

