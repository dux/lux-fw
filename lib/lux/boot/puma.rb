# Puma::DSL extension for config/puma.rb.
#
#   require 'lux/boot/puma'
#   Dotenv.load
#
#   lux_boot do |is_prod|
#     # optional overrides, e.g.
#     # threads 1, 32 if is_prod    # lower it if the box is memory-tight
#   end
#
# lux_boot applies the standard lux puma config (port, threads, pidfile,
# state_path, tmp_restart, logging, worker count) and yields is_prod so the
# host app can override any directive at parse time. Defaults:
#
#   port            ENV['PUMA_PORT'] || ENV['PORT'] || 3000
#   threads         1, 100  (an open SSE stream parks one for its lifetime)
#   plugin          :tmp_restart
#   production      stdout -> ./log, workers 2 (environment derived from LUX_ENV)
#   development     stdout on-screen (no redirect), banner host rewritten to lvh.me
#
# When clustered (workers >= 2 after overrides) it installs three hooks:
#
#   before_fork        - disconnect any Sequel DBs held by the master
#   on_worker_boot     - disconnect inherited sockets, load ./config/app, then
#                        re-arm anything that cannot survive a fork
#   on_worker_shutdown - disconnect on worker exit
#
# Disconnects are a no-op without preload_app! (master holds no DB handles)
# but become load-bearing the moment it is enabled - inherited socket FDs
# from the master are dropped before the worker touches the pool.

# Opt-in: only extend Puma::DSL when the host app has already loaded puma.
# In lux-fw dev (no puma) this file is a no-op so the loader sweep is safe.
ENV['OBJC_DISABLE_INITIALIZE_FORK_SAFETY'] ||= 'YES'

return unless defined?(Puma::DSL)

module Lux
  module Boot
    module PumaDSL
      def lux_boot(&block)
        is_prod   = ENV['LUX_ENV'] == 'production'
        puma_port = ENV['PUMA_PORT'] || ENV['PORT'] || 3000

        plugin       :tmp_restart # restart on touch of tmp/restart.txt
        port          puma_port
        log_requests  false
        pidfile       './tmp/puma.%s.pid'   % puma_port
        state_path    './tmp/puma.%s.state' % puma_port

        # An SSE stream parks a thread for as long as the client stays connected,
        # so the max thread count is also the concurrent-stream ceiling per
        # worker. 32 is too tight once a page holds a stream open; 100 leaves
        # room. Idle threads are cheap - blocked ones hold no DB connection.
        threads       1, 100

        # debug/reload are resolved from ENV (set by `lux s` or the deploy unit),
        # not here. prod runs clustered with file logging; dev/test stay single
        # and keep stdout on-screen.
        if is_prod
          stdout_redirect './log/puma.log', './log/puma_errors.log'
          workers 2
        else
          # Puma logs the resolved socket address ('0.0.0.0:3000', '[::]:3000'),
          # which no terminal turns into a link. lvh.me resolves to 127.0.0.1 and
          # is the dev host the rest of lux assumes (config.host, cookie domains),
          # so swap the host in and keep the port puma actually bound. Dev only -
          # a formatter here would also drop the [pid] prefix clustered prod logs
          # get from Puma::LogWriter::PidFormatter.
          log_formatter do |str|
            str.sub %r{(?<=Listening on http://)(?:\[[^\]]*\]|[^:\s]+)}, 'lvh.me'
          end
        end

        # let the host app override any directive at parse time (master)
        block&.call(is_prod)

        return if @options[:workers].to_i < 2

        # puma 8 renamed on_worker_* -> before_worker_*; keep both eras working
        boot_hook = respond_to?(:before_worker_boot)     ? :before_worker_boot     : :on_worker_boot
        down_hook = respond_to?(:before_worker_shutdown) ? :before_worker_shutdown : :on_worker_shutdown

        before_fork do
          Sequel::DATABASES.each(&:disconnect) if defined?(Sequel)
        end

        send boot_hook do
          Sequel::DATABASES.each(&:disconnect) if defined?(Sequel)
          require './config/app'

          # The app is loaded in the master before the first fork, so anything
          # it started there - the channel broker's LISTEN thread above all -
          # exists in the master only; the worker inherits the socket and
          # nothing that reads it. Re-arm here, after the fork. No-op unless
          # the app asked for a listener.
          Lux::Browser::Channel.broker.after_fork! if defined?(Lux::Browser::Channel)
        end

        send down_hook do
          Sequel::DATABASES.each(&:disconnect) if defined?(Sequel)
        end
      end
    end
  end
end

Puma::DSL.include Lux::Boot::PumaDSL
