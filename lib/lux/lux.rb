# frozen_string_literal: true

require_relative '../common/class_callbacks'
require_relative 'cache/cache'

module Lux
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

  define_method(:cli?)         { $0 == 'pry' || $0.end_with?('/run.rb') || $0.end_with?('/rspec') || ENV['RACK_ENV'] == 'test' }
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

  # main rack response
  def call env=nil
    state  = Lux::Current.new env
    app    = Lux::Application.new state
    app.render
  rescue => error
    if Lux.config(:dump_errors)
      raise error
    else
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
    data ? Lux::Error.render(data) : Lux::Error
  end

  def log what=nil
    return unless Lux.config(:log_to_stdout)
    puts what || yield
  end

  def plugin *args
    args.first ? Lux::Plugin.loader(*args) : Lux::Plugin
  end

  # if block given, simple new thread bg job
  # if string given, eval it in bg
  # if object given, instance it and run it
  def delay *args, &block
    if block_given?
      puts 'add'

      t = Thread.new do
        begin
          block.call
        rescue => e
          Lux.logger(:delay_errors).error [e.message, e.backtrace]
        end
      end

      BACKGROUND_THREADS.push t
    elsif args[0]
      # Lux.delay(mail_object, :deliver)
      Lux::DelayedJob.push(*args)
    else
      Lux::DelayedJob
    end
  end

  def load_tasks
    require_relative '../../tasks/loader.rb'
  end

  def ram_cache key
    MCACHE[key] = nil if Lux.config(:compile_assets)
    MCACHE[key] ||= yield
  end

  def start
    puts Config.start!
  end

  def serve rack_handler
    Object.class_callback :after_boot, Lux::Config.new, rack_handler

    rack_handler.run self
  end

  def speed loops=1
    render_start = Time.monotonic
    loops.times { yield }
    num = (Time.monotonic - render_start) * 1000
    num = "#{num.round(1)} ms"
    loops == 1 ? num : "Done #{loops.to_s.sub(/(\d)(\d{3})$/,'\1s \2')} loops in #{num}"
  end

  def logger name=nil
    name ||= ENV.fetch('RACK_ENV').downcase

    MCACHE['lux-logger-%s' % name] ||=
    Logger.new('./log/%s.log' % name).tap do |it|
      it.formatter = Lux.config.logger_formater
    end
  end
end

require_relative 'config/config'