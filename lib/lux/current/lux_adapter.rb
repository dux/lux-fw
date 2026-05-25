module Lux
  def current
    Thread.current[:lux] ||= Lux::Current.new('/mock')
  end

  # Shim - implementation lives in Lux::Defer (lib/lux/defer/defer.rb).
  #
  # Runs the block on a pool-backed background worker. Pool size is
  # Lux.config.defer_pool_size (default 3) and workers exit after 60s
  # idle. If the queue is saturated the job runs inline in the caller
  # (caller-runs overflow) - work is never dropped.
  #
  # The parent request context is NOT silently installed inside the worker;
  # it is passed as an explicit argument (a shallow dup of Lux.current) so
  # the caller decides what to read from it. Zero-arity blocks stay
  # compatible.
  #
  #   Lux.defer do |ctx|
  #     # ctx is Lux.current.dup from the parent thread
  #     # Lux.current inside this thread is a fresh instance
  #   end
  #
  #   Lux.defer(context: user) { |u| Mailer.welcome(u).deliver }
  #
  # Errors and timeouts are logged to Lux.logger(:defer_worker).
  def defer context: nil, timeout: nil, &block
    Lux::Defer.submit(context: context, timeout: timeout, &block)
  end
end

# exposes lux shortcut anywhere
class Object
  def lux
    Thread.current[:lux]
  end
end
