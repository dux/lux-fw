# frozen_string_literal: true

require 'clean-annotations'

require_relative 'cache/cache'

module ::Lux
  extend self

  ENV_PROD       = ENV['RACK_ENV'] == 'production' unless defined?(ENV_PROD)
  CACHE_SERVER ||= Lux::Cache.new
  VERSION      ||= File.read File.expand_path('../../../.version', __FILE__).chomp
  CONFIG       ||= Hashie::Mash.new
  APP_ROOT     ||= Pathname.new(ENV.fetch('APP_ROOT') { Dir.pwd }).freeze
  FW_ROOT      ||= Pathname.new(File.expand_path('../../', File.dirname(__FILE__))).freeze
  EVENTS       ||= {}
  MCACHE       ||= {}

  BACKGROUND_THREADS ||= []
  # Kernel.at_exit { BACKGROUND_THREADS.each { |t| t.join } }

  define_method(:rake?)        { $0.end_with?('/rake') }
  define_method(:test?)        { ENV['RACK_ENV'] == 'test' }
  define_method(:prod?)        { ENV_PROD }
  define_method(:production?)  { ENV_PROD }
  define_method(:dev?)         { !ENV_PROD }
  define_method(:development?) { !ENV_PROD }
  define_method(:cache)        { CACHE_SERVER }
  define_method(:secrets)      { @secrets ||= Lux::Config::Secrets.new.load }
  define_method(:root)         { APP_ROOT }
  define_method(:fw_root)      { FW_ROOT }
  define_method(:event)        { Lux::EventBus }
  define_method(:require_all)  { |folder| Lux::Config.require_all folder }
  alias :load :require_all

  # main rack response
  def call env=nil
    current = Lux::Current.new env
    app     = Lux::Application.new current
    app.render
  rescue => error
    if Lux.config(:dump_errors)
      raise error
    else
      log error.backtrace
      [500, {}, ['Server error: %s' % error.message]]
    end
  end

  def env key=nil
    if key
      value = ENV[key]
      die "ENV['#{key}'] not found" if value.nil?
      value
    else
      ENV['RACK_ENV']
    end
  end

  def config key=nil
    if key
      value = CONFIG[key]
      die 'Lux.config.%s not found' % key if value.nil?
      value.kind_of?(Proc) ? value.call() : value
    else
      CONFIG
    end
  end

  def thread
    Thread.current[:lux] ||= {}
  end

  def current
    thread[:page] ||= Lux::Current.new('/mock')
  end

  def app &block
    block ? Lux::Application.class_eval(&block) : Lux::Application
  end

  def error data=nil
    if data
      raise Lux::Error.new(500, data)
    else
      Lux::Error
    end
  end

  # simple log to stdout
  def log what=nil
    return unless Lux.config(:log_to_stdout)
    puts what || yield
  end

  # simple interface to plugins
  # Lux.plugin :foo
  # Lux.plugin
  def plugin *args
    args.first ? Lux::Config::Plugin.load(*args) : Lux::Config::Plugin
  end

  # load rake tasks + including ones in plugins
  def load_tasks
    if ARGV.first.to_s.end_with?(':')
      run 'rake -T | grep %s' % ARGV.first
      exit
    end

    require_relative '../../tasks/loader.rb'
  end

  # in memory cache, used on app init, no need for Mutex
  def ram_cache key
    MCACHE[key] = nil if Lux.config(:compile_assets)
    MCACHE[key] ||= yield
  end

  # initialize the Lux application
  def boot &block
    # load plugins
    Lux.config.plugins.each do |name|
      Lux.plugin name
    end

    Config.boot!
    instance_exec &block
  end

  # must be called when serving web pages from rackup
  def serve rack_handler
    @rackup_start = true

    # Boot Lux
    Object.class_callback :boot, Lux::Application, rack_handler
    rack_handler.run self
  end

  # simple block to calc block execution speed
  def speed
    render_start = Time.monotonic
    yield
    num = (Time.monotonic - render_start) * 1000
    '%s ms' % num.round(1)
  end

  # Lux.logger(:foo).warn 'bar'
  def logger name=nil
    name ||= ENV.fetch('RACK_ENV').downcase

    MCACHE['lux-logger-%s' % name] ||=
    Logger.new(Lux.prod? || Lux.cli? ? './log/%s.log' % name : STDOUT).tap do |it|
      it.formatter = Lux.config.logger_formater
    end
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

  def cli?
    return true if rake?
    return true if Lux.config.lux_config_loaded && !@rackup_start
    false
  end

  # if block given, simple new thread bg job
  #   Lux.delay(self) { |object| ... }
  # if string given, write it to a job server
  #   Lux.delay(mail_object, :deliver)
  # without params return module
  #   Lux.delay
  def delay *args
    if block_given?
      lux_env = thread
      t = Thread.new do
        begin
          Thread.current[:lux] = lux_env
          Timeout::timeout(Lux.config(:delay_timeout)) do
            yield *args
          end
        rescue => e
          if Lux.config(:log_to_stdout)
            ap ['Lux.delay error', e.message, e.backtrace]
          else
            Lux.logger(:delay_errors).error [e.message, e.backtrace]
          end
        end
      end

      # BACKGROUND_THREADS.push t
    elsif args[0]
      # Lux.delay(mail_object, :deliver)
      Lux::DelayedJob.write *args
    else
      Lux::DelayedJob
    end
  end
end

require_relative 'config/config'