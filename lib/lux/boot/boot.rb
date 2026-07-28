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

    BOOT_MUTEX ||= Mutex.new

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

      # first requests race on threaded servers (falcon --threaded, puma):
      # without the lock a second thread sees @booted and dispatches into a
      # half-booted app. @booted flips inside the lock before the work, so a
      # reentrant boot! on the booting thread stays a no-op.
      BOOT_MUTEX.synchronize do
        return if @booted
        @booted = true

        require_env!
        Lux.init_env
        Lux.dotenv
        # .env may carry LUX_DEBUG / LUX_RELOAD, and anything that logged
        # before boot has already built the flags off the pre-dotenv ENV.
        # Re-parse; runtime overrides and silent are untouched.
        Lux.flags.reload_env!
        bundler_require!
        Lux.config
        set_defaults

        yield if block_given?

        plugins = Lux::Plugin.normalize_names(Lux.config[:plugins])
        Lux.plugin(*plugins) if plugins.any?

        unless Lux.env.test?
          Lux.shell.info plugins.any? ? "Lux plugins: #{plugins.join(', ')}" : 'Lux: no plugins'
          puts start_info
        end
      end
    end

    def booted?
      @booted == true
    end

    private

    # Refuse to boot without an explicit environment. Empty means the host
    # forgot to set it - fail loud rather than silently assuming dev.
    def require_env!
      return unless ENV['LUX_ENV'].to_s.empty?
      Lux.shell.die 'LUX_ENV not defined'
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
      Bundler.require :default, (ENV['LUX_ENV'] || 'development').to_sym
    end

    # Framework defaults for anything config.yaml did not declare.
    #
    # This runs AFTER the config load (see boot!), so a plain `=` would overwrite
    # what the host declared - config.yaml would silently do nothing for every
    # key listed here. `||=` is wrong too: a default of `true` would flip an
    # explicit `false` back on. Key existence is the only correct test, which is
    # what set_default does. A block defers the value so it is not computed for a
    # key the host already set.
    def set_defaults
      ENV['TZ'] ||= 'UTC'

      # Delay
      set_default(:delay_timeout) { Lux.env.dev? ? 3600 : 30 }
      set_default :defer_pool_size, 3

      # Logger
      set_default(:log_level) { Lux.debug? ? :info : :error }
      set_default :logger_path_mask, './log/%s.log'
      set_default :logger_files_to_keep, 3
      set_default :logger_file_max_size, 10_240_000
      set_default :logger_formatter, nil

      # Other
      set_default :asset_root, false
      set_default :plugins, []

      # What an id looks like, app-wide: the router (nav.map_path), the :ref
      # column type, Lux::Utils::Ref and load_models all resolve through it, so
      # they cannot drift apart. A registered name, or `{ name => attrs }`.
      # See Lux::Application::Nav::Base.register for what is available.
      set_default :ref_format, :string

      # Serve static files is on by default
      set_default :serve_static_files, true
    end

    def set_default key, value = nil
      return if Lux.config.key?(key)

      Lux.config[key] = block_given? ? yield : value
    end

    def start_info
      @start_info ||= begin
        info = []

        info.push "Lux env:  #{Lux.env.to_s.colorize(:yellow)}"

        toggles = Lux::Environment::Flags::FLAGS.keys.map do |name|
          on = Lux.send("#{name}?")
          on ? "#{name} (yes)".colorize(:yellow) : "#{name} (no)".colorize(:green)
        end
        info.push "Lux flags: #{toggles.join(', ')}"

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
