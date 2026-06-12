require 'logger'

module Lux
  LOGGER_CACHE ||= {}

  # Lux.logger — default logger (STDERR in dev, silent in test, ./log/error.log in prod)
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
  # Skips block evaluation when the logger would drop the message (e.g. log_level=:error
  # in production), so callers can freely pass colorize/sprintf/`Lux.app_caller` blocks
  # without paying for them in prod.
  # When LOG() has been called in the current request, screen logs are suppressed
  # so only LOG output is visible.
  def log what = nil, &block
    return unless Lux.logger.info?
    return if Lux.respond_to?(:current) && Lux.current.var[:lux_disable_screen_log]
    what = block.call if block
    Lux.logger.info(what) if what
  end

  private

  def default_logger
    @default_logger ||= begin
      if Lux.env.test?
        l = Logger.new(IO::NULL)
      elsif Lux.env.production?
        l = Logger.new('./log/error.log', Lux.config.logger_files_to_keep, Lux.config.logger_file_max_size)
      else
        # STDERR (not STDOUT) so CLI tasks like `lux render` can pipe clean machine output.
        l = Logger.new(STDERR)
        l.formatter = proc { |_, _, _, msg| "#{msg}\n" }
      end

      # Default uses Lux.mode.debug? so the logger works before Lux.boot! has populated config.
      level = Lux.config.key?(:log_level) ? Lux.config[:log_level] : (Lux.mode.debug? ? :info : :error)
      l.level = level == :info ? Logger::INFO : Logger::ERROR
      l
    end
  end
end
