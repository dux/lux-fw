# Puma::DSL extension for config/puma.rb.
#
#   require 'lux/boot/puma'
#
#   lux_boot worker_count do
#     require_relative 'app'
#   end
#
# worker_count < 2: no-op. Single-process puma loads the app via config.ru.
#
# worker_count >= 2: installs three hooks:
#
#   before_fork        - disconnect any Sequel DBs held by the master
#   on_worker_boot     - disconnect inherited sockets, then run user block
#   on_worker_shutdown - disconnect on worker exit
#
# Disconnects are a no-op without preload_app! (master holds no DB handles)
# but become load-bearing the moment it is enabled - inherited socket FDs
# from the master are dropped before the worker touches the pool.

# Opt-in: only extend Puma::DSL when the host app has already loaded puma.
# In lux-fw dev (no puma) this file is a no-op so the loader sweep is safe.
return unless defined?(Puma::DSL)

module Lux
  module Boot
    module PumaDSL
      def lux_boot(worker_count, &block)
        return if worker_count.to_i < 2

        workers worker_count

        before_fork do
          Sequel::DATABASES.each(&:disconnect) if defined?(Sequel)
        end

        on_worker_boot do
          Sequel::DATABASES.each(&:disconnect) if defined?(Sequel)
          block&.call
        end

        on_worker_shutdown do
          Sequel::DATABASES.each(&:disconnect) if defined?(Sequel)
        end
      end
    end
  end
end

Puma::DSL.include Lux::Boot::PumaDSL
