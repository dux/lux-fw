require 'yaml'
require 'deep_merge'

module Lux
  module Config
    extend self

    def app_boot
      # mock first request to boot app, we need to access config in app somehow
      Lux.app.new('/init-boot-config').run_callback :config

      after_boot_check

      puts start_info
    end

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

    def start_info
      @load_info ||= proc do
        production_opts = %i(code_reload dump_errors screen_log)

        opts = production_opts.map do |key|
          env_value = env_value_of key
          Lux.config[key] = env_value ? env_value == 'yes' : Lux.config[key]

          data = "#{key} (%s)" % [Lux.config[key] ? :yes : :no]
          Lux.config[key] ? data.yellow : data.green
        end

        if $lux_start_time.class == Array
          # $lux_start_time ||= Time.now added to Gemfile
          speed = 'in %s sec (%s gems, %s app)' % [
            time_diff($lux_start_time[0]).white,
            time_diff($lux_start_time[0], $lux_start_time[1]),
            time_diff($lux_start_time[1]),
          ]
        else
          speed = 'in %s sec' % time_diff($lux_start_time).white
        end

        info = []
        info.push '* Config: %s' % opts.join(', ')
        info.push "* Lux loaded in #{ENV['RACK_ENV']} mode, #{speed}, uses #{ram.to_s.white} MB RAM with total of #{Gem.loaded_specs.keys.length.to_s.white} gems in spec"
        info.join($/)
      end.call
    end

    def set_defaults
      ENV['TZ'] = 'UTC'

      # Show server errors to a client
      Lux.config.dump_errors = Lux.env.dev?

      # Automatic code reloads in development
      Lux.config.code_reload = Lux.env.dev?

      # Dump all logs to screen
      Lux.config.screen_log = Lux.env.dev?

      # Delay
      Lux.config.delay_timeout = 30

      # Create controller methods if templates exist (as Rails does)
      Lux.config.use_autoroutes = true

      # Logger
      Lux.config.logger_path_mask     = './log/%s.log'
      Lux.config.logger_default       = Lux.env.dev? ? STDOUT : nil
      Lux.config.logger_default       = nil if env_value_of(:screen_log) == 'no'
      Lux.config.logger_files_to_keep = 3
      Lux.config.logger_file_max_size = 10_240_000
      Lux.config.logger_formatter     = nil

      # Other
      Lux.config.asset_root            = false
      Lux.config[:plugins]           ||= []
      Lux.config[:error_logger]      ||= Proc.new do |error|
        ap [error.message, error.class, Lux::Error.mark_backtrace(error)]
      end

      ###

      # Serve static files is on by default
      Lux.config.serve_static_files = true

      # Etag and cache tags reset after deploy
      Lux.config.deploy_timestamp = File.mtime('./Gemfile').to_i.to_s

      # inflector
      String.inflections do |inflect|
        inflect.plural   'bonus', 'bonuses'
        inflect.plural   'clothing', 'clothes'
        inflect.plural   'people', 'people'
        inflect.singular /news$/, 'news'
      end
    end

    def after_boot_check
      # deafult host is required
      unless Lux.config.host.to_s.include?('http')
        raise 'Invalid "Lux.config.host"'
      end
    end

    def app_timeout
      @app_timeout || Lux.current.try('[]', :app_timeout) || Lux.config[:app_timeout] || (Lux.env.dev? ? 3600 : 30)
    rescue
      debugger if Lux.env.dev?

      30
    end

    # './config/secrets.yaml'
    # default:
    #   development:
    #      foo:
    #   production:
    #      bar:
    def load
      source = Pathname.new './config/config.yaml'

      if source.exist?
        data = YAML.safe_load source.read, aliases: true
        base = data['default'] || data['base']

        if base
          base.deep_merge(data[Lux.env.to_s] || {})
        else
          raise "Secrets :default root not defined in %s" % source
        end
      else
        puts Lux.info '%s not found' % source
        {}
      end
    end

    private

    def time_diff time1, time2 = Time.now
      ((time2 - time1)).round(2).to_s
    end

    def env_value_of key
      value = ENV["LUX_#{key.to_s.upcase}"]
      value = 'yes' if value == 'true'
      value = 'no' if value == 'false'
      value
    end
  end
end
