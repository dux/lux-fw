# App-boot orchestration: env resolution, .env, gemfile load, config.yaml,
# defaults, plugins. Loaded after Shell/Environment/Config so it can call
# into them directly. Idempotent - safe to call from config/env.rb, from
# `bin/lux`'s :app task, and defensively from Lux::Application#call.
#
# Public entry is Lux.boot! (thin delegator in boot/lux_adapter.rb).

module Lux
  module Boot
    extend self

    # Seeded in lib/lux-fw.rb before gems load so amazing_print/sequel/etc.
    # require time is counted. ||= so this file is safe to require directly
    # in test / tooling paths that skip the gem entry.
    STARTED_AT ||= Time.now

    def started_at
      STARTED_AT
    end

    # Optional block runs after env / config.yaml / defaults are set but
    # before plugins load - the spot to override config values plugins
    # read during their own boot:
    #
    #   Lux.boot! do
    #     Lux.config.localize = false
    #     Lux.config.app_timeout = 10
    #   end
    def call
      return if @booted
      @booted = true

      Lux.init_env
      Lux.dotenv
      bundler_require!
      Lux.config
      set_defaults

      yield if block_given?

      plugins = Lux::Plugin.normalize_names(Lux.config[:plugins])
      if plugins.any?
        Lux.plugin(*plugins)
        Lux.shell.info "Lux plugins: #{plugins.join(', ')}"
      else
        Lux.shell.info 'Lux: no plugins'
      end

      puts start_info
    end

    def booted?
      @booted == true
    end

    # Run `Bundler.require :default, <env>` once, so the host doesn't have
    # to put it in config/env.rb. No-op when Bundler isn't loaded (e.g.
    # standalone script using lux-fw outside of a Gemfile) or when
    # LUX_SKIP_BUNDLER_REQUIRE is set (escape hatch).
    def bundler_require!
      return if @bundler_required
      return unless defined?(Bundler)
      return if ENV['LUX_SKIP_BUNDLER_REQUIRE']

      @bundler_required = true
      Bundler.require :default, (ENV['RACK_ENV'] || 'development').to_sym
    end

    def set_defaults
      ENV['TZ'] ||= 'UTC'

      # Delay
      Lux.config.delay_timeout = Lux.env.dev? ? 3600 : 30

      # Logger
      Lux.config.log_level            = Lux.mode.debug? ? :info : :error
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

    def start_info
      @start_info ||= begin
        info = []

        info.push "Lux env:  #{Lux.env.to_s.colorize(:yellow)}"

        flags = %w(debug reload).map do |name|
          on = Lux.mode.send("#{name}?")
          on ? "#{name} (yes)".colorize(:yellow) : "#{name} (no)".colorize(:green)
        end
        info.push "Lux mode: #{flags.join(', ')}"

        speed = 'in %s sec' % (Time.now - started_at).round(2).to_s.colorize(:white)

        info.push "* Lux loaded #{speed}, uses #{ram.to_s.colorize(:white)} MB RAM with total of #{Gem.loaded_specs.keys.length.to_s.colorize(:white)} gems in spec"
        info.join($/)
      end
    end

    def ram
      Lux.shell.exec('ps', '-o', 'rss', '-p', $$.to_s).split("\n").last.to_i / 1000
    end
  end
end
