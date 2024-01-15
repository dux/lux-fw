require 'yaml'
require 'deep_merge'

module Lux
  module Config
    extend self

    def ram
      `ps -o rss -p #{$$}`.chomp.split("\n").last.to_i / 1000
    end

    def start_info
      @load_info ||= proc do
        info = []

        config = []
        %w(no_cache reload_code show_errors screen_log).each do |name|
          value = Lux.env.send("#{name}?")
          config.push value ? "#{name} (yes)".yellow : "#{name} (no)".green
        end
        info.push "Lux env: #{config.join(', ')}"

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

        info.push "* Lux loaded in #{ENV['RACK_ENV']} mode, #{speed}, uses #{ram.to_s.white} MB RAM with total of #{Gem.loaded_specs.keys.length.to_s.white} gems in spec"
        info.join($/)
      end.call
    end

    def set_defaults
      ENV['LUX_ENV'] ||= ''
      ENV['TZ'] ||= 'UTC'

      # Delay
      Lux.config.delay_timeout = Lux.env.dev? ? 3600 : 30

      # Logger
      Lux.config.logger_path_mask     = './log/%s.log'
      Lux.config.logger_files_to_keep = 3
      Lux.config.logger_file_max_size = 10_240_000
      Lux.config.logger_formatter     = nil

      # Other
      Lux.config.use_autoroutes       = false
      Lux.config.asset_root           = false
      Lux.config[:plugins]           ||= []
      Lux.config[:error_logger]      ||= Proc.new do |error|
        ap [error.message, error.class, Lux::Error.mark_backtrace(error)]
      end

      ###

      # Serve static files is on by default
      Lux.config.serve_static_files = true

      # Etag and cache tags reset after deploy
      Lux.config.deploy_timestamp = File.mtime('./Gemfile').to_i.to_s
    end

    def app_timeout
      @app_timeout || Lux.current.try('[]', :app_timeout) || Lux.config[:app_timeout] || (Lux.env.dev? ? 3600 : 30)
    rescue
      30
    end

    # './config/secrets.yaml'
    # default:
    #   development:
    #      foo:
    #   production:
    #      foo:
    def load
      source = Pathname.new './config/config.yaml'

      if source.exist?
        data = YAML.safe_load source.read, aliases: true
        base = data['default'] || data['base']

        if base
          base.deep_merge!(data[Lux.env.to_s] || {})
          base['production'] = data['production']
          base
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

    def env_value_of key, default = :_undef
      value = ENV["LUX_#{key.to_s.upcase}"].to_s
      value = true if ['true', 't', 'yes'].include?(value)
      value = false if ['false', 'f', 'no'].include?(value)

      if default == :_undef
        value
      else
        value.nil? ? deafult : value
      end
    end
  end
end
