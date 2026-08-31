# RSpec boot for the expect/double style specs (see .rspec for the pattern).
# The Minitest world (spec/**) boots via test_helper.rb and runs through the
# Hammerfile spec task - the two harnesses never co-load.

ENV['LUX_ENV'] = 'test'
ENV['SECRET']   = 'test-secret'

require 'bundler'
Bundler.require

require_relative '../lib/lux-fw'

# Mute per-statement DB log + Lux.shell.info chatter for the suite.
Lux.silent true

Lux.config.secret         = ENV['SECRET']
Lux.config.host           = 'http://test'
Lux.config.compile_assets = false
Lux.config[:log_level]    = :error unless Lux.config.key?(:log_level)

require 'logger'
Lux.instance_variable_set(:@default_logger, Logger.new(IO::NULL))
