require 'timeout'

module Lux
  def app &block
    block ? Lux::Application.class_eval(&block) : Lux::Application
  end
  alias :application :app

  # main rack response - delegates through the cached rack chain so
  # `run Lux` in config.ru gets the same middleware as Lux().
  def call env = nil
    Lux.boot! unless booted?
    rack_app.call(env)
  end

  # Rack chain wrapped around the real dispatch. Built once after boot
  # so Lux.config[:serve_static_files] is resolved.
  #
  # Static layout: /assets/* -> ./public/, long cache for css/js, cascade
  # falls through to Lux on a miss. Hosts that want a different layout
  # set Lux.config.serve_static_files = false and mount their own
  # Rack::Static via Lux() or a custom config.ru.
  def rack_app
    @rack_app ||= begin
      dispatch = method(:rack_dispatch)
      if Lux.config[:serve_static_files] == false
        dispatch
      else
        Rack::Builder.new do
          use Rack::Static,
            urls: ['/assets'],
            root: 'public',
            cascade: true,
            header_rules: [
              [/\.(css|js)$/, { 'cache-control' => 'public, max-age=86400' }]
            ]
          run dispatch
        end.to_app
      end
    end
  end

  def rack_dispatch env
    Timeout::timeout Lux::Boot::Config.app_timeout do
      app  = Lux::Application.new env
      app.render_base || raise('No RACK response given')
    end
  rescue => err
    Lux.logger.error Lux::Error.format(err, message: true)

    if Lux.mode.debug?
      raise
    else
      [500, {}, ['Server error: %s' % err.message]]
    end
  end
end

# Rack builder DSL: `Lux` in config.ru. Optional block is forwarded to
# Lux::Application (class_eval). Defined at top level so it is callable
# inside Rack::Builder's instance_eval, where `self` is the builder.
def Lux &block
  raise 'Lux error: Rack not found' unless self.class == Rack::Builder
  Lux::Application.class_eval(&block) if block
  run Lux
end
