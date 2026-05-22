require 'timeout'

module Lux
  def app &block
    block ? Lux::Application.class_eval(&block) : Lux::Application
  end
  alias :application :app

  # main rack response
  def call env = nil
    # Defensive boot: if the host's config.ru forgot to require config/env
    # (or there is no config/env), bring the app up on first request. The
    # call is idempotent so once-per-process is the only real cost.
    Lux.boot! unless booted?

    Timeout::timeout Lux::Config.app_timeout do
      app  = Lux::Application.new env
      app.render_base || raise('No RACK response given')
    end
  rescue => err
    Lux.logger.error Lux::Error.format(err, message: true)

    if Lux.mode.log?
      raise
    else
      [500, {}, ['Server error: %s' % err.message]]
    end
  end
end

# Rack builder DSL: `run Lux` in config.ru with optional block forwarded to
# Lux::Application. Defined at top level so it is callable inside Rack::Builder.
def Lux &block
  raise 'Lux error: Rack not found' unless self.class == Rack::Builder
  $rack_handler = self
  Lux::Application.class_eval(&block) if block
  run Lux
  puts Lux::Config.start_info
end
