# Puma::DSL extension for config/puma.rb.
#
#   require 'lux/boot/puma'
#   Dotenv.load
#
#   lux_boot do |is_prod|
#     # optional overrides, e.g.
#     # threads 1, 32 if is_prod
#   end
#
# lux_boot applies the standard lux puma config (port, threads, pidfile,
# state_path, tmp_restart, logging, worker count) and yields is_prod so the
# host app can override any directive at parse time. Defaults:
#
#   port            ENV['PUMA_PORT'] || ENV['PORT'] || 3000
#   threads         1, 32
#   plugin          :tmp_restart
#   production      stdout -> ./log, environment production, workers 2
#   development     stdout -> /dev/null
#
# When clustered (workers >= 2 after overrides) it installs three hooks:
#
#   before_fork        - disconnect any Sequel DBs held by the master
#   on_worker_boot     - disconnect inherited sockets, then load ./config/app
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
        is_prod   = ENV['RACK_ENV'] == 'production'
        puma_port = ENV['PUMA_PORT'] || ENV['PORT'] || 3000

        plugin       :tmp_restart # restart on touch of tmp/restart.txt
        port          puma_port
        log_requests  false
        pidfile       './tmp/puma.%s.pid'   % puma_port
        state_path    './tmp/puma.%s.state' % puma_port
        threads       1, 32

        if is_prod
          stdout_redirect './log/puma.log', './log/puma_errors.log'
          environment 'production'
          workers 2
        else
          stdout_redirect '/dev/null'
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
        end

        send down_hook do
          Sequel::DATABASES.each(&:disconnect) if defined?(Sequel)
        end
      end
    end
  end
end

Puma::DSL.include Lux::Boot::PumaDSL
