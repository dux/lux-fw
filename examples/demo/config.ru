require 'securerandom'
require 'lux-fw'
require_relative './config/environment'

Lux.boot!

# Sessions need Lux.config.secret. config/config.yaml is gitignored here so the
# framework repo never carries one, so fall back to a throwaway per-boot value -
# fine for a demo (sessions just do not survive a restart). Set SECRET in the
# env, or write config/config.yaml, for a stable one.
Lux.config[:secret] ||= ENV['SECRET'] || SecureRandom.hex(24)

# controllers and routes live in ./app - the framework does not autoload them
Dir.require_all './app'

run Lux
