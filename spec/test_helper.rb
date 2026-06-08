ENV['LUX_ENV'] = 'test'
ENV['SECRET']   = 'test-secret'

require 'bundler'
Bundler.require

require_relative '../lib/lux-fw'

# Mute per-statement DB log + Lux.shell.info chatter for the suite. Set before
# the first Lux.config access below so even boot-time info stays quiet.
Lux.mode.silent true

Lux.config.secret         = ENV['SECRET']
Lux.config.host           = 'http://test'
Lux.config.compile_assets = false
Lux.config[:log_level]    = :error unless Lux.config.key?(:log_level)

# Silence Lux.logger during the test suite. Specs that need to capture
# logger output (see spec/lux_tests/lux_spec.rb) swap @default_logger
# back to a StringIO inside their own `before`/`after`.
require 'logger'
Lux.instance_variable_set(:@default_logger, Logger.new(IO::NULL))

# Load test scaffolding (Minitest + Lux::Test::Factory + helpers).
# Lives outside boot.rb so production lux never pulls it in.
require_relative '../lib/lux/test/test'

# Top-level `factory` shortcut so spec/factories.rb can write
# `factory :foo do ... end` outside any describe block.
# Inside a describe/it, the same `factory` method is provided by
# Lux::Test::Case (mixed into Minitest::Spec) - this top-level def
# is only for blueprint loading.
def factory *args, &block
  if args.empty? && !block
    Lux::Test::Factory
  elsif args.empty? && block
    Lux::Test::Factory.instance_exec(&block)
  else
    Lux::Test::Factory.define(*args, &block)
  end
end

# Single home for every factory blueprint used by any spec.
require_relative './factories'

require 'minitest/autorun'
