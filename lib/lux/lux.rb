module ::Lux
  extend self

  VERSION ||= File.read File.expand_path('../../../.version', __FILE__).chomp

  def root
    @lux_app_root ||= Pathname.new(ENV.fetch('APP_ROOT') { Dir.pwd }).freeze
  end

  def fw_root
    @lux_fw_root ||= Pathname.new(File.expand_path('../../', File.dirname(__FILE__))).freeze
  end

  # main rack response
  def call env=nil
    app  = Lux::Application.new env
    data = app.render || raise('No RACK response given')
  rescue => err
    error.log err

    if Lux.config.dump_errors
      raise err
    else
      [500, {}, ['Server error: %s' % error.message]]
    end
  end

  # simple block to calc block execution speed
  def speed
    render_start = Time.monotonic
    yield
    num = (Time.monotonic - render_start) * 1000
    '%s ms' % num.round(1)
  end

  def info text
    puts '* %s' % text.magenta
  end

  def run command
    puts command.light_black
    logger(:system_run).info command
    system command
  end

  def die text
    puts text.red
    logger(:system_die).error text
    exit
  end

  def app_caller
    app_line   = caller.find { |line| !line.include?('/lux-fw/') && !line.include?('/.') }
    app_line ? app_line.split(':in ').first.sub(Lux.root.to_s, '.') : nil
  end
end

###

def Lux
  if self.class == Rack::Builder
    $rack_handler = self
    run Lux
  end

  Lux::Config.app_boot
end

###

require_relative 'environment/environment'
require_relative 'environment/lux_adapter'

require_relative 'config/config'
require_relative 'config/lux_adapter'

if $lux_start_time
  # for better start stats add $lux_start_time ||= Time.now to begginging of Gemfile
  $lux_start_time = [$lux_start_time, Time.now]
else
  $lux_start_time = Time.now
end
