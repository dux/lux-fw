require 'logger'

module Lux
  LOGGER_CACHE ||= {}

  # Lux.logger — default logger (STDOUT in dev, ./log/error.log in prod)
  # Lux.logger(:foo) — named file logger (writes to ./log/foo.log)
  def logger name = nil
    return default_logger unless name

    LOGGER_CACHE[name] ||= begin
      output_location = Lux.config.logger_path_mask % name
      logger = Logger.new output_location, Lux.config.logger_files_to_keep, Lux.config.logger_file_max_size

      if Lux.config.logger_formatter
        logger.formatter = Lux.config.logger_formatter
      end

      logger
    end
  end

  # Lux.log 'message' or Lux.log { 'lazy message' }
  # convenience shortcut for Lux.logger.info
  def log what = nil, &block
    what = block.call if block
    Lux.logger.info(what) if what
  end

  private

  def default_logger
    @default_logger ||= begin
      if Lux.env.production?
        l = Logger.new('./log/error.log', Lux.config.logger_files_to_keep, Lux.config.logger_file_max_size)
      else
        l = Logger.new(STDOUT)
        l.formatter = proc { |_, _, _, msg| "#{msg}\n" }
      end

      l.level = Lux.config.log_level == :info ? Logger::INFO : Logger::ERROR
      l
    end
  end
end
