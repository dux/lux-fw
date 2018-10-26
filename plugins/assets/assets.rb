['./tmp', './public', './public/assets', './tmp/assets'].each { |d| `mkdir #{d}` unless Dir.exist?(d) }

require_relative 'lib/lux_assets'
require_relative 'lib/lux_assets_asset'
require_relative 'assets_helper'
require_relative 'assets_routes'


