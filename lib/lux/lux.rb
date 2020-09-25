# frozen_string_literal: true

# require_relative 'cache/cache'

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
    app = Lux::Application.new env
    app.render
  rescue => error
    if Lux.config.dump_errors
      raise error
    else
      log error.backtrace
      [500, {}, ['Server error: %s' % error.message]]
    end
  end

  # initialize the Lux application
  def boot &block
    # load plugins
    (Lux.config.plugins || []).each do |name|
      Lux.plugin name
    end

    Config.boot!

    instance_exec &block if block
  end

  # must be called when serving web pages from rackup
  def serve rack_handler
    $rackup_start = true

    # Boot Lux
    Lux::Application.run_callback :boot, rack_handler
    rack_handler.run self
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
    app_line = caller
      .find { |line| !line.include?('/lux-fw/') && !line.include?('/.') }
      .split(':in ')
      .first
      .sub(Lux.root.to_s, '.')
  end
end

require_relative 'environment/environment'
require_relative 'environment/lux_adapter'

require_relative 'config/config'
require_relative 'config/lux_adapter'
