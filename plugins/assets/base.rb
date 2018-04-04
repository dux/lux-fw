Lux::Config.require_all Lux.fw_root.join('plugins/assets/mini_assets/*')

require_relative 'mini_assets/mini_assets'

require_relative 'lib/assets_plug'
require_relative 'lib/helper_module_adapter'

['./tmp', './public', './public/assets', './tmp/assets'].each { |d| `mkdir #{d}` unless Dir.exist?(d) }

