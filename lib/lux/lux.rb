module ::Lux
  extend self

  CONFIG  ||= {}.to_hwia
  VERSION ||= File.read File.expand_path('../../../.version', __FILE__).chomp

  def root
    @lux_app_root ||= Pathname.new(ENV.fetch('APP_ROOT') { Dir.pwd }).freeze
  end

  def fw_root
    @lux_fw_root ||= Pathname.new(File.expand_path('../../', File.dirname(__FILE__))).freeze
  end

  # main rack response
  def call env = nil
    Timeout::timeout Lux::Config.app_timeout do
      app  = Lux::Application.new env
      app.render_base || raise('No RACK response given')
    end
  rescue => err
    error.log err

    if Lux.config.dump_errors
      raise err
    else
      [500, {}, ['Server error: %s' % err.message]]
    end
  end

  # simple block to calc block execution speed
  def speed
    render_start = Time.monotonic
    yield
    num = (Time.monotonic - render_start) * 1000
    if num > 1000
      '%s sec' % (num/1000).round(2)
    else
      '%s ms' % num.round(1)
    end
  end

  def info text
    if text.class == Array
      text.each {|line| self.info line }
    else
      puts '* %s' % text.magenta
    end
  end

  def run command
    puts command.light_black
    logger(:system_run).info command
    system command
  end

  def die text
    puts "Lux FATAL: #{text}".red
    logger(:system_die).error text
    exit
  end

  def app_caller
    app_line   = caller.find { |line| !line.include?('/lux-') && !line.include?('/.') && !line.include?('(eval)') }
    app_line ? app_line.split(':in ').first.sub(Lux.root.to_s, '.') : nil
  end

  def delay time_to_live = nil
    Thread.new do
      time_to_live ||= Lux.config.delay_timeout

      unless time_to_live.is_a?(Numeric)
        raise 'Time to live is not integer (seconds)'
      end

      Timeout::timeout time_to_live do
        yield
      end
    end
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
