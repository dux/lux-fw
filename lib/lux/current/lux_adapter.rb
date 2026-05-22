require 'timeout'

module Lux
  def current
    Thread.current[:lux] ||= Lux::Current.new('/mock')
  end

  # Spawn a background thread with a clean Lux.current.
  #
  # The parent request context is NOT silently installed inside the thread.
  # Instead it is passed to the block as an explicit argument (a shallow dup
  # of Lux.current), so the caller decides what to read from it.
  #
  #   Lux.defer do |ctx|
  #     # ctx is Lux.current.dup from the parent thread
  #     # Lux.current inside this thread is a fresh instance
  #   end
  #
  #   Lux.defer(context: user) { |u| Mailer.welcome(u).deliver }
  #
  # Zero-arity blocks stay compatible: Lux.defer { ... }.
  def defer context: nil, timeout: nil, &block
    raise ArgumentError, 'Block not given' unless block

    context = Lux.current.dup if context.nil?
    timeout ||= Lux.config.delay_timeout
    raise 'Timeout is not numeric (seconds)' unless timeout.is_a?(Numeric)

    Thread.new do
      # new thread starts with Thread.current[:lux] == nil; do not install
      # parent context. Any Lux.current access here lazily builds a clean one.
      begin
        ::Timeout::timeout(timeout) do
          block.arity == 0 ? block.call : block.call(context)
        end
      rescue => e
        Lux.logger.error ['Lux.defer error: %s' % e.message, e.backtrace].join($/)
      ensure
        Thread.current[:lux] = nil
      end
    end
  end
end

# exposes lux shortcut anywhere
class Object
  def lux
    Thread.current[:lux]
  end
end
