module Lux
  # Lux.logger(:foo).warn 'bar'
  def logger name=nil
    name          ||= Lux.env.to_s
    output_location = Lux.config.logger_output_location.call(name)

    CACHE['lux-logger-%s' % name] ||=
    Logger.new(output_location).tap do |it|
      it.formatter = Lux.config.logger_formater
    end
  end

  # simple log to stdout
  def log what=nil, &block
    Lux.config.logger_stdout.call what || block
  end
end