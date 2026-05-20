require 'yaml'
require 'deep_merge'

module Lux
  module Config
    extend self

    def ram
      `ps -o rss -p #{$$}`.chomp.split("\n").last.to_i / 1000
    end

    def start_info
      @load_info ||= begin
        info = []

        info.push "Lux env:  #{Lux.env.to_s.colorize(:yellow)}"

        flags = %w(log errors reload).map do |name|
          on = Lux.mode.send("#{name}?")
          on ? "#{name} (yes)".colorize(:yellow) : "#{name} (no)".colorize(:green)
        end
        info.push "Lux mode: #{flags.join(', ')}"

        if $lux_start_time.class == Array
          # $lux_start_time ||= Time.now added to Gemfile
          speed = 'in %s sec (%s gems, %s app)' % [
            time_diff($lux_start_time[0]).colorize(:white),
            time_diff($lux_start_time[0], $lux_start_time[1]),
            time_diff($lux_start_time[1]),
          ]
        else
          speed = 'in %s sec' % time_diff($lux_start_time).colorize(:white)
        end

        info.push "* Lux loaded #{speed}, uses #{ram.to_s.colorize(:white)} MB RAM with total of #{Gem.loaded_specs.keys.length.to_s.colorize(:white)} gems in spec"
        info.join($/)
      end
    end

    def set_defaults
      ENV['TZ'] ||= 'UTC'

      # Delay
      Lux.config.delay_timeout = Lux.env.dev? ? 3600 : 30

      # Logger
      Lux.config.log_level            = Lux.mode.log? ? :info : :error
      Lux.config.logger_path_mask     = './log/%s.log'
      Lux.config.logger_files_to_keep = 3
      Lux.config.logger_file_max_size = 10_240_000
      Lux.config.logger_formatter     = nil

      # Other
      Lux.config.use_autoroutes       = false
      Lux.config.asset_root           = false
      Lux.config[:plugins]           ||= []

      ###

      # Serve static files is on by default
      Lux.config.serve_static_files = true

      # Etag and cache tags reset after deploy
      Lux.config.deploy_timestamp = File.mtime('./Gemfile').to_i.to_s
    end

    def app_timeout
      # Peek at the existing thread-local Current instead of triggering lazy
      # creation - app_timeout runs before Application#initialize installs the
      # real Current, so calling Lux.current here would build a throwaway /mock
      # Current and autoload Rack::MockRequest (and on Ruby 4 + rack 3.1, drag
      # in cgi/cookie which is no longer a default gem).
      cur = Thread.current[:lux]
      per_request = cur && cur[:app_timeout]
      per_request || Lux.config[:app_timeout] || (Lux.env.dev? ? 3600 : 30)
    rescue
      30
    end

    # './config/secrets.yaml'
    # default is shared + specific envs
    # default:
    #   foo:
    # development:
    #   foo:
    # production:
    #   foo:
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
        Lux.info '%s not found' % source
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
        value.nil? ? default : value
      end
    end
  end
end
