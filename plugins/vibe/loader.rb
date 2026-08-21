# Explicit load order for the vibe plugin.
#
# Only the pure-Ruby core is loaded here (git, restart, opencode client, commit
# message). The Sinatra harness lives in lib/vibe/server.rb and is required by
# `lux docker:vibe:server` alone - an app booting with this plugin enabled must not pull
# sinatra/puma in.

require_relative 'lib/vibe'
