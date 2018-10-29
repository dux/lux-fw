ENV['RACK_ENV'] = 'test'
ENV['SECRET']  = 'test-secret'

# load gems
Bundler.require

# load lux
require_relative '../lib/lux-fw.rb'

Lux.config.secret         = ENV['SECRET']
Lux.config.host           = 'http://test'
Lux.config.compile_assets = false
Lux.start

class Object
  def rr data
    ap ['- start', data, '- end']
  end
end

Lux.config.log_to_stdout    = false
Lux.config.auto_code_reload = false
Lux.config.dump_errors      = true

# basic config
RSpec.configure do |config|
  # Use color in STDOUT
  config.color = true

  # Use color not only in STDOUT but also in pagers and files
  config.tty = true

  # Use the specified formatter
  config.formatter = :documentation # :progress, :html, :json, CustomFormatterClass
end
