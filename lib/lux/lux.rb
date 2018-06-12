# frozen_string_literal: true

require_relative '../common/class_callbacks'
require_relative 'cache/cache'

module Lux
  extend self

  ENV_PROD     = ENV['RACK_ENV']    == 'production'
  ENV_DEV      = ENV['RACK_ENV']    == 'development'
  ENV_TEST     = ENV['RACK_ENV']    == 'test'
  LUX_CLI      = $0 == 'pry' || $0.end_with?('/run.rb') || $0.end_with?('/rspec') || ENV['RACK_ENV'] == 'test'
  CACHE_SERVER = Lux::Cache.new

  VERSION = File.read File.expand_path('../../../.version', __FILE__).chomp
  CONFIG ||= Hashie::Mash.new
  EVENTS ||= {}
  MCACHE ||= {}

  BACKGROUND_THREADS ||= []
  Kernel.at_exit { BACKGROUND_THREADS.each { |t| t.join } }

  define_method(:prod?)   { ENV_PROD }
  define_method(:dev?)    { ENV_DEV }
  define_method(:test?)   { ENV_TEST }
  define_method(:cli?)    { LUX_CLI }
  define_method(:cache)   { CACHE_SERVER }
  define_method(:thread)  { Thread.current[:lux] }
  define_method(:secrets) { @app_secrets ||= Lux::Config::Secrets.new.load }

  # main rack response
  def call env=nil
    state  = Lux::Current.new env
    app    = Lux::Application.new state
    app.render
  rescue => e
    raise e if Lux.config(:show_server_errors)

    [500, {}, ['Lux server error']]
  end

  def env key=nil
    return ENV['RACK_ENV'] unless key
    die "ENV['#{key}'] not found" if ENV[key].nil?
    ENV[key]
  end

  def config key=nil
    return CONFIG unless key
    die 'Lux.config.%s not found' % key if CONFIG[key].nil?
    CONFIG[key].kind_of?(Proc) ? CONFIG[key].call() : CONFIG[key]
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

  def root
    @@lux_app_root ||= Pathname.new(Dir.pwd).freeze
  end

  def fw_root
    @@lux_fw_root ||= Pathname.new(File.expand_path('../../', File.dirname(__FILE__))).freeze
  end

  def error data
    current.response.status 500
    Lux::Error.show(data)
  end

  def log what
    return unless Lux.config(:log_to_stdout)
    puts what
  end

  def on name, ref=nil, &proc
    EVENTS[name] ||= []

    if block_given?
      puts "* event: #{name} defined".white
      EVENTS[name].push(proc)
    else
      for func in EVENTS[name]
        ref.instance_eval(&func)
      end
    end
  end

  # if block given, simple new thread bg job
  # if string given, eval it in bg
  # if object given, instance it and run it
  def delay *args
    if block_given?
      BACKGROUND_THREADS.push Thread.new { yield }
    elsif args[0]
      # Lux.delay(mail_object, :deliver)
      Lux::DelayedJob.push(*args)
    else
      Lux::DelayedJob
    end
  end

  def speed loops=1
    render_start = Time.monotonic
    loops.times { yield }
    num = (Time.monotonic - render_start) * 1000
    num = "#{num.round(1)} ms"
    loops == 1 ? num : "Done #{loops.to_s.sub(/(\d)(\d{3})$/,'\1s \2')} loops in #{num}"
  end

  # load specific plugin
  def plugin name
    dir  = '%s/plugins/%s' % [Lux.fw_root, name]
    base = '%s/base.rb' % dir

    if File.exist?(base)
      load base
    else
      Lux::Config.require_all('%s/*' % dir)
    end
  end

  def load_tasks
    require_relative '../../tasks/loader.rb'
  end

  def ram_cache key
    MCACHE[key] = nil if Lux.config(:compile_assets)
    MCACHE[key] ||= yield
  end
end

require_relative 'config/config'