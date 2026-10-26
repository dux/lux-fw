ENV['LUX_ENV'] = 'test'
ENV['SECRET']   = 'test-secret'

require 'bundler'
Bundler.require

require_relative '../lib/lux-fw'

# Mute per-statement DB log + Lux.shell.info chatter for the suite. Set before
# the first Lux.config access below so even boot-time info stays quiet.
Lux.silent true

Lux.config.secret         = ENV['SECRET']
Lux.config.host           = 'http://test'
Lux.config.compile_assets = false
Lux.config[:log_level]    = :error unless Lux.config.key?(:log_level)

# Load test scaffolding (Minitest + Lux::Test::Factory + helpers).
# Lives outside boot.rb so production lux never pulls it in.
require_relative '../lib/lux/test/test'

# Top-level `factory` shortcut so spec/factories.rb can write
# `factory :foo do ... end` outside any describe block.
# Inside a describe/it, the same `factory` method is provided by
# Lux::Test::Case (mixed into Minitest::Spec). Defined on `main` only, so it
# does not become a private Object#factory on every object.
def self.factory *args, &block
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
