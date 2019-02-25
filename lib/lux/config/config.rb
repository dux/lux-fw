# frozen_string_literal: true

# $LOADED_FEATURES.select{ |f| f.index('/app/') || f.index('/lux/') }

require 'yaml'

module Lux::Config
  extend self

  # requires all files recrusive in, with spart sort
  def require_all dir_path
    dir_path = dir_path.to_s.sub(/\/$/, '')
    dir_path = './%s' % dir_path if dir_path =~ /^\w/

    raise '* is not allowed' if dir_path.include?('*')

    glob = []
    glob.push 'echo'
    glob.push '%s/*'           % dir_path
    glob.push '%s/*/*'         % dir_path
    glob.push '%s/*/*/*'       % dir_path
    glob.push '%s/*/*/*/*'     % dir_path
    glob.push '%s/*/*/*/*/*'   % dir_path
    glob.push '%s/*/*/*/*/*/*' % dir_path
    glob.push "| tr ' ' '\n'"
    glob.push "| grep .rb"
    list = `#{glob.join(' ')}`.split("\n")

    list.select{ |o| o.index('.rb') }.each do |ruby_file|
      begin
        require ruby_file
      rescue => e
        ap Lux::Error.split_backtrace e
      end
    end
  end

  # preview config in development
  def show_config
    for k,v in Lux.config
      next if v.kind_of?(Hash)
      puts "* config :#{k} = #{v.kind_of?(Hash) ? '{...}' : v}"
    end
  end

  def live_require_check!
    $live_require_check ||= Time.now

    watched_files = $LOADED_FEATURES
      .select{ |f| f.include?(Lux.root.to_s) || f.include?(ENV['LUX_GEMS'] || 'not!defiend')}
      .select {|f| File.mtime(f) > $live_require_check }

    for file in watched_files
      Lux.log ' Reloaded: .%s' % file.split(Lux.root.to_s).last.yellow
      load file
    end

    $live_require_check = Time.now
  end

  def ram
    `ps -o rss -p #{$$}`.chomp.split("\n").last.to_i / 1000
  end

  def start!
    Object.class_callback :config, Lux::Application
    start_info $lux_start_time
  end

  def start_info start=nil
    return @load_info if @load_info

    production_mode = true
    production_opts = [
      [:compile_assets,   false],
      [:auto_code_reload, false],
      [:dump_errors,      false],
      [:log_to_stdout,    false],
    ]

    opts = production_opts.map do |key, production_value|
      config_test     = Lux.config(key)
      config_ok       = production_value == config_test
      production_mode = false unless config_ok

      data = "#{key} (%s)" % [config_test ? :yes : :no]
      config_ok ? data : data.yellow
    end

    mode  = production_mode ? 'production'.green : 'development'.yellow
    speed = start ? ' in %s sec' % ((Time.now - start)).round(1).to_s.white : nil

    info = []
    info.push '* Config: %s' % opts.join(', ')
    info.push "* Lux loaded #{mode} mode#{speed}, uses #{ram.to_s.white} MB RAM with total of #{Gem.loaded_specs.keys.length.to_s.white} gems in spec"

    @load_info = info.join($/)
    puts @load_info if start
    @load_info
  end

  def init!
    # Show server errors to a client
    Lux.config.dump_errors = Lux.dev?

    # Log debug output to stdout
    Lux.config.log_to_stdout = Lux.dev?

    # Automatic code reloads in development
    Lux.config.auto_code_reload = Lux.dev?

    # Runtime compile js and css assets
    Lux.config.compile_assets = Lux.dev?

    Lux.config.session_cookie_domain = false
    Lux.config.asset_root            = false

    ###

    if ENV['LUX_MODE'].to_s.downcase == 'log'
      Lux.config.dump_errors      = false
      Lux.config.auto_code_reload = false
      Lux.config.compile_assets   = false
    end

    ###

    # Default error logging
    Lux.config.error_logger = proc do |error|
      ap Lux.error.split_backtrace(error)

      'no-key'
    end

    # Default mail logging
    Lux.config.on_mail = proc do |mail|
      Lux.logger(:email).info "[#{self.class}.#{@_template} to #{mail.to}] #{mail.subject}"
    end

    # default event bus error handle
    Lux.config.on_event_bus_error = proc do |error, name|
      Lux.logger(:event_bus).error '[%s] %s' % [name, error.message]
    end

    # server static files
    Lux.config.serve_static_files = true

    # Template to show when displaying unhandled server side errors
    Lux.config.server_error_template = proc do |text|
      text = text.to_s.gsub('<', '&lt;')
      text = text.to_s.gsub($/,'<br />')

      %[<html>
          <head>
            <title>Server error (#{Lux.current.response.status})</title>
          </head>
          <body style="background:#fff; font-size:12pt; font-family: Arial; padding: 20px;">
            <h3>HTTP error #{Lux.current.response.status} in #{Lux.config.app.name}</h3>
            <pre style="color:red; padding:10px; background-color: #eee; border: 1px solid #ccc; font-family:'Lucida console'; line-height: 15pt;">#{text}</pre>
            <br>
            <a href="https://httpstatuses.com/#{Lux.current.response.status}" target="http_error">more info on http error</a>
          </body>
        </html>]
    end

    # Simpler log formatter
    Lux.config.logger_formater = proc do |severity, datetime, progname, msg|
      date = datetime.utc
      msg  = '%s: %s' % [severity, msg] if severity != 'INFO'
      "[%s] %s\n" % [date, msg]
    end

    # inflector
    String.inflections do |inflect|
      inflect.plural   'bonus', 'bonuses'
      inflect.plural   'clothing', 'clothes'
      inflect.plural   'people', 'people'
      inflect.singular /news$/, 'news'
    end
  end
end

if Lux.cli?
  class Object
    def reload!
      Lux::Config.live_require_check!
    end
  end
end