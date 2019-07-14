# frozen_string_literal: true

require_relative '../common/class_callbacks'
require_relative 'cache/cache'

module ::Lux
  extend self

  ENV_PROD       = ENV['RACK_ENV'] == 'production' unless defined?(ENV_PROD)
  CACHE_SERVER ||= Lux::Cache.new
  VERSION      ||= File.read File.expand_path('../../../.version', __FILE__).chomp
  CONFIG       ||= Hashie::Mash.new
  APP_ROOT     ||= Pathname.new(Dir.pwd).freeze
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
    state  = Lux::Current.new env
    app    = Lux::Application.new state
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

  def current
    Thread.current[:lux][:page] ||= Lux::Current.new('/mock')
  end

  def current=(what)
    Thread.current[:lux][:page] = what
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

  # if block given, simple new thread bg job
  # if string given, eval it in bg
  # if object given, instance it and run it
  def delay *args
    if block_given?
      lux_env = Thread.current[:lux]
      t = Thread.new do
        begin
          Thread.current[:lux] = lux_env
          Timeout::timeout(30) do
            yield *args
          end
        rescue => e
          Lux.logger(:delay_errors).error [e.message, e.backtrace]
        end
      end

      # BACKGROUND_THREADS.push t
    elsif args[0]
      # Lux.delay(mail_object, :deliver)
      Lux::DelayedJob.push *args
    else
      Lux::DelayedJob
    end
  end

  # load rake tasks + including ones in plugins
  def load_tasks
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
    puts command.gray
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

  def job *args
    if block_given?
      @job_server = yield
      @job_server = "Lux::DelayedJob::#{name.to_s.capitalize}".constantize if @job_server.is_a?(Symbol)
    elsif args[0]
      @job_server.push *args
    else
      @job_server
    end
  end
end

require_relative 'config/config'