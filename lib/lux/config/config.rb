# frozen_string_literal: true

require 'yaml'

module Lux
  module Config
    extend self

    # preview config in development
    def show_config
      for k,v in Lux.config
        next if v.kind_of?(Hash)
        puts "* config :#{k} = #{v.kind_of?(Hash) ? '{...}' : v}"
      end
    end

    def ram
      `ps -o rss -p #{$$}`.chomp.split("\n").last.to_i / 1000
    end

    def boot!
      Lux::Application.run_callback :config
      Lux.config.lux_config_loaded = true
      start_info $lux_start_time
    end

    def start_info start=nil
      return @load_info if @load_info

      production_mode = true
      production_opts = [
        [:auto_code_reload, false],
        [:dump_errors,      false],
        [:log_to_stdout,    false],
      ]

      opts = production_opts.map do |key, production_value|
        config_test     = Lux.config[key]
        config_ok       = production_value == config_test
        production_mode = false unless config_ok

        data = "#{key} (%s)" % [config_test ? :yes : :no]
        config_ok ? data : data.yellow
      end

      mode  = production_mode ? 'production'.green : 'development'.yellow
      speed = start ? ' in %s sec' % ((Time.now - start)).round(1).to_s.white : nil

      info = []
      info.push '* Config: %s' % opts.join(', ')
      info.push "* Lux loaded #{mode} mode#{speed}, uses #{ram.to_s.white} MB RAM with total of #{Gem.loaded_specs.keys.length.to_s.white} gems in spec}"

      @load_info = info.join($/)
      puts @load_info if start
      @load_info
    end

    def init!
      # Show server errors to a client
      Lux.config.dump_errors = Lux.env.dev?

      # Log debug output to stdout
      Lux.config.log_to_stdout = Lux.env.dev?

      # Automatic code reloads in development
      Lux.config.auto_code_reload = Lux.env.dev?

      # Delay
      Lux.config.delay_timeout = 30

      # Create controller methods if templates exist (as Rails does)
      Lux.config.use_autoroutes = true

      # Logger
      Lux.config.loger_files_to_keep = 3
      Lux.config.loger_file_max_size = 1_024_000

      # Other
      Lux.config.session_cookie_domain = false
      Lux.config.asset_root            = false
      Lux.config[:plugins]           ||= []
      Lux.config[:error_logger]      ||= Proc.new do |error|
        ap Lux::Error.split_backtrace(error)
      end

      ###

      if Lux.env.log?
        Lux.config.dump_errors      = false
        Lux.config.auto_code_reload = false
      end

      ###

      # Serve static files is on by default
      Lux.config.serve_static_files = true

      # inflector
      String.inflections do |inflect|
        inflect.plural   'bonus', 'bonuses'
        inflect.plural   'clothing', 'clothes'
        inflect.plural   'people', 'people'
        inflect.singular /news$/, 'news'
      end
    end
  end
end
