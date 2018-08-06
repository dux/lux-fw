# Logs DB queries in console
# to active just load the file
if Lux.config(:log_to_stdout)
  logger = Logger.new(STDOUT)

  logger.formatter = proc { |severity, datetime, progname, msg|
    elms = msg.split(/\(|s\)\s/, 3)
    time = (elms[1].to_f * 1000).round(1)

    if c = Thread.current[:db_q]
      if c && c[:last] != msg
        c[:last] = msg
        c[:time] += elms[1].to_f
        c[:cnt]  += 1

        Lux.log " #{c[:cnt].to_s.rjust(2)}. #{time} : #{elms[2].to_s.cyan}\n"
      end
    end
  }

  DB.loggers << logger
end
