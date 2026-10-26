module Lux
  # Per-thread context. Lazily built without a request outside of one (console,
  # jobs, scripts), so Lux.ctx.request is the "inside a request?" check.
  def ctx
    Thread.current[:lux] ||= Lux::Context.new
  end

  # Shim - implementation lives in Lux::Defer (lib/lux/defer/defer.rb).
  #
  # Runs the block on a pool-backed background worker. Pool size is
  # Lux.config.defer_pool_size (default 3) and workers exit after 60s
  # idle. If the queue is saturated the job runs inline in the caller
  # (caller-runs overflow) - work is never dropped.
  #
  # The live request is never shared with the worker. Lux.ctx inside is
  # rebuilt from Lux.ctx.snapshot (request id, method, url, user), and the
  # block gets that frozen snapshot unless an explicit context is passed.
  #
  #   Lux.defer do |snap|
  #     # snap.request_id / snap.request_method / snap.url / snap.ip / snap.user
  #   end
  #
  #   Lux.defer(context: user) { |u| Mailer.welcome(u).deliver }
  #
  # Errors and timeouts go to Lux.logger(:defer_worker) and Lux.error.log.
  def defer context: nil, timeout: nil, &block
    Lux::Defer.submit(context: context, timeout: timeout, &block)
  end
end
