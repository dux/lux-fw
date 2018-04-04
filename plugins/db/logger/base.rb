# Logs DB queries in console
# to active just load the file
logger = Logger.new(STDOUT)

logger.formatter = proc { |severity, datetime, progname, msg|
  elms = msg.split(/\(|s\)\s/, 3)
  time = (elms[1].to_f * 1000).round(1)
  if Thread.current[:db_q]
    Thread.current[:db_q][:time] += elms[1].to_f
    Thread.current[:db_q][:cnt] += 1

    # append debug=true as query-string to see database queries
    Lux.log(" #{Thread.current[:db_q][:cnt].to_s.rjust(2)}. #{time} : #{elms[2].to_s.cyan}\n") if Thread.current[:db_q]
  end
}

DB.loggers << logger

