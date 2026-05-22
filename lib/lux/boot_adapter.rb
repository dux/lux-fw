# Top-level "app boot" orchestration. The framework is loaded by
# `require 'lux-fw'` (which runs boot.rb); this is what brings the app
# itself up - env resolution, .env, gemfile load, config.yaml, plugins.
#
# Idempotent: safe to call from config/env.rb, from `bin/lux`'s :app
# task, and as a defensive call inside Lux::Application#call.

module Lux
  # Optional block runs after env / config.yaml / defaults are set but
  # *before* plugins load - the spot to override config values that
  # plugins read during their own boot:
  #
  #   Lux.boot! do
  #     Lux.config.localize = false
  #     Lux.config.app_timeout = 10
  #   end
  def boot!
    return if @booted
    @booted = true

    init_env
    dotenv
    bundler_require!
    config
    Lux::Config.set_defaults

    yield if block_given?

    plugins = Lux::Plugin.normalize_names(Lux.config[:plugins])
    if plugins.any?
      Lux.plugin(*plugins)
      Lux.shell.info "Lux plugins: #{plugins.join(', ')}"
    else
      Lux.shell.info 'Lux: no plugins'
    end

    puts Lux::Config.start_info
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
end
