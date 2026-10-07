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
  # The live request is never shared with the worker. Lux.current inside is
  # rebuilt from Lux.current.snapshot (request id, method, url, user), and the
  # block gets that frozen snapshot unless an explicit context is passed.
  #
  #   Lux.defer do |ctx|
  #     # ctx.request_id / ctx.request_method / ctx.url / ctx.ip / ctx.user
  #   end
  #
  #   Lux.defer(context: user) { |u| Mailer.welcome(u).deliver }
  #
  # Errors and timeouts go to Lux.logger(:defer_worker) and Lux.error.log.
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
