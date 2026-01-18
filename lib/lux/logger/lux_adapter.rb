require 'logger'

module Lux
  LOGGER_CACHE ||= {}

  # Lux.logger(:foo).warn 'bar'
  def logger name = nil
    raise "Logger name is required" unless name

    LOGGER_CACHE[name] ||= begin
      output_location = Lux.config.logger_path_mask % name
      LOGGER_CACHE[name] = Logger.new output_location,  Lux.config.logger_files_to_keep, Lux.config.logger_file_max_size

      if Lux.config.logger_formatter
        LOGGER_CACHE[name].formatter = Lux.config.logger_formatter
      end
      LOGGER_CACHE[name]
    end
  end

  def log what = nil, &block
    return unless Lux.env.screen_log?
    what = block.call if block
    print what.to_s + "\n" if what
  end
end
