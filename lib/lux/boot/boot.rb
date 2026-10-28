# App-boot orchestration: env resolution, .env, gemfile load, config.yaml,
# defaults, plugins. Loaded after Shell/Environment/Config so it can call
# into them directly. Idempotent - safe to call from config/env.rb, from
# `bin/lux`'s :app task, and defensively from Lux::Router#call.
#
# Public entry is Lux.boot! (thin delegator in boot/lux_adapter.rb).

require 'monitor'

module Lux
  module Boot
    extend self

    # Seeded in lib/lux-fw.rb before gems load so amazing_print/sequel/etc.
    # require time is counted. ||= so this file is safe to require directly
    # in test / tooling paths that skip the gem entry.
    STARTED_AT ||= Time.now

    # reentrant: a plugin loader / config/app.rb may call Lux.boot! again on the booting thread
    BOOT_LOCK ||= Monitor.new

    def started_at
      STARTED_AT
    end

    # Optional block runs after env / config.yaml / defaults are set but
    # before plugins load - the spot to override config values plugins
    # read during their own boot:
    #
    #   Lux.boot! do
    #     Lux.config.localize = false
    #     Lux.config.serve_static_files = false
    #   end
    def call
      return if @booted

      # first requests race on threaded servers (falcon --threaded, puma):
      # other threads block on the lock until the boot finishes. @booted is
      # set only after a full boot; @booting makes a reentrant boot! on the
      # booting thread a no-op instead of a deadlock.
      BOOT_LOCK.synchronize do
        return if @booted || @booting
        @booting = true
        begin
          # .env may carry LUX_ENV itself, so load it before the check
          Lux.dotenv
          require_env!
          Lux.init_env
          # .env may carry LUX_DEBUG / LUX_RELOAD, and anything that logged
          # before boot has already built the flags off the pre-dotenv ENV.
          # Re-parse; runtime overrides and silent are untouched.
          Lux.flags.reload_env!
          bundler_require!
          set_boot_defaults
          warn_config_typos @declared_keys

          yield if block_given?

          plugins = Lux::Plugin.normalize_names(Lux.config[:plugins])

          # app constants first, so they win over same-named plugin mount files
          Lux::Root.autoload_skip = Lux::Plugin.defined_constants(plugins)
          Lux::Root.autoload! Lux.root
          Lux.plugin(*plugins) if plugins.any?

          # Only a process that holds browser connections needs to receive;
          # publishing works anywhere without a listener. Clustered servers
          # re-arm after fork - see the puma worker hook in boot/puma.rb.
          Lux::Browser::Channel.broker.listen! if Lux.runtime.web?

          unless Lux.env.test?
            Lux.shell.info plugins.any? ? "Lux plugins: #{plugins.join(', ')}" : 'Lux: no plugins'
            puts start_info
          end

          @booted = true
        ensure
          @booting = false
        end
      end
    end

    def booted?
      @booted == true
    end

    # Lux.config runs this once on the freshly loaded config.yaml hash, so the
    # keys the logger and defer read exist before boot!. Returns config.
    def apply_defaults config
      @declared_keys = config.keys.map(&:to_s)
      set_defaults config
      config
    end

    private

    # Refuse to boot without an explicit environment (shell or .env). Only a
    # host that never sets LUX_ENV (e.g. a bare config.ru) trips this.
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
      Bundler.require :default, Lux.env.to_s.to_sym
    end

    # Framework defaults for anything config.yaml did not declare.
    #
    # A plain `=` would overwrite what the host declared. `||=` is wrong too:
    # a default of `true` would flip an explicit `false` back on. Key existence
    # is the only correct test, which is what set_default does. A block defers
    # the value so it is not computed for a key the host already set.
    def set_defaults config
      ENV['TZ'] ||= 'UTC'

      # Delay
      set_default(config, :delay_timeout) { Lux.env.dev? ? 3600 : 30 }
      set_default config, :defer_pool_size, 3

      # Logger
      set_default config, :logger_path_mask, './log/%s.log'
      set_default config, :logger_files_to_keep, 3
      set_default config, :logger_file_max_size, 10_240_000
      set_default config, :logger_formatter, nil

      # Other
      set_default config, :asset_root, false
      set_default config, :plugins, []

      # What an id looks like, app-wide: nav.map_path, the :ref column type and
      # Lux::Ref.generate all resolve through it, so they cannot drift apart.
      # A registered name, or `{ name => attrs }`. See Lux::Ref.register.
      set_default config, :ref_format, :string

      # Serve static files is on by default
      set_default config, :serve_static_files, true

      # true when the app is reachable through Cloudflare only (dboss
      # cloudflare_only): CF-* headers (CF-Connecting-IP, CF-IPCountry) are then
      # always trusted. Off, they are dropped unless the forwarding hop is a
      # Cloudflare edge address.
      set_default config, :cloudflare, false

      # Device Bound Session Credentials over https (Chrome/Edge); see Lux::Context::Dbsc
      set_default config, :session_dbsc, true
    end

    # Defaults read from ENV that .env may supply (LUX_DEBUG, DB_MAIN): config
    # can load before Lux.dotenv, so these wait for boot!. Until then the
    # logger derives its level from Lux.debug? itself.
    def set_boot_defaults
      set_default(Lux.config, :log_level) { Lux.debug? ? :info : :error }

      # Browser push (/_lux_/stream) goes cross-process by default. The usual
      # shape is a web process plus a job process, and an in-process default
      # fails silently there - the job publishes and no browser ever hears it.
      # Two exceptions, both of which have nothing to bridge: test is
      # single-process, and an app with no main DB has no NOTIFY to send.
      set_default(Lux.config, :channel_url) { Lux.env.test? || !Lux::Db.url_for(:main) ? nil : 'postgres:main' }
    end

    def set_default config, key, value = nil
      (@default_keys ||= []).push key.to_s
      return if config.key?(key)

      config[key] = block_given? ? yield : value
    end

    # A misspelled framework key in config.yaml is otherwise silently ignored
    # while set_defaults fills in the real one. Unknown keys stay allowed -
    # Lux.config doubles as Lux.secrets.
    def warn_config_typos declared
      checker = DidYouMean::SpellChecker.new(dictionary: @default_keys.uniq)

      (declared - @default_keys).each do |key|
        hint = checker.correct(key).first or next
        Lux.shell.info 'Lux config: unknown key "%s", did you mean "%s"?' % [key, hint]
      end
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
      Lux.shell.exec('ps', '-o', 'rss=', '-p', $$.to_s) {}.to_s.split("\n").last.to_i / 1000
    end
  end
end
