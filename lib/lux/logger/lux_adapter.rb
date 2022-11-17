module Lux
  LOGGER_CACHE ||= {}

  # Lux.logger(:foo).warn 'bar'
  def logger name = nil, otps = {}
    if !name
      _logger_default
    elsif Lux.config.logger_default == STDOUT
      logger = Logger.new STDOUT
      logger.formatter = proc do |severity, _, _, msg|
         "LOGGER(#{name}) #{severity}: #{msg}\n"
      end
      logger
    else
      unless LOGGER_CACHE[name]
        output_location = Lux.config.logger_path_mask % name
        LOGGER_CACHE[name] = Logger.new output_location,  Lux.config.logger_files_to_keep, Lux.config.logger_file_max_size

        if Lux.config.logger_formatter
          LOGGER_CACHE[name].formatter = Lux.config.logger_formatter
        end
      end

      LOGGER_CACHE[name]
    end
  end

  def log what = nil, &block
    what = block.call if block

    if Lux.config.logger_default == STDOUT
      # do not show log headers when printing
      # print is thread safer than puts
      print what.to_s + "\n"
    else
      _logger_default.info what
    end
  end

  def _logger_default
    LOGGER_CACHE[:default] ||= Logger.new Lux.config.logger_default
  end
end
