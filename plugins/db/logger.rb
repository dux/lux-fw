# Logs DB queries in console
# to active just load the file

require 'logger'

logger = Logger.new STDOUT
logger.formatter = proc do |severity, datetime, progname, msg|
  elms = msg.split(/\(|s\)\s/, 3)
  time = (elms[1].to_f * 1000).round(1)
  formated = " DB: #{elms[2].to_s.cyan} (#{time} ms, #{Lux.app_caller})"

  if c = Thread.current[:db_q]
    if c && c[:last] != msg
      c[:last] = msg
      c[:time] += elms[1].to_f
      c[:cnt]  += 1
      Lux.log formated
    end
  else
    if ENV['DB_LOG'] || (!Lux.env.rake? && !msg.include?('SELECT "pg_attribute"."attname"') && !msg.end_with?('SELECT NULL'))
      $last_sql_command = msg
      Lux.log formated
    end
  end
end

if ENV['RAKE_ENV'] != 'test' || ENV['DB_LOG'] == 'true'
  # error logger to stdout
  Lux.config.sequel_dbs = [] unless Lux.config[:sequel_dbs]
  Lux.config.sequel_dbs.each do |db|
    db.loggers << logger
  end

  if Lux.env.screen_log?
    Lux.app do
      before do
        Thread.current[:db_q] = { time: 0.0, cnt: 0, list:{} }
      end

      after do
        if Thread.current[:db_q] && Thread.current[:db_q][:cnt] > 0
          Lux.log " #{Thread.current[:db_q][:cnt]} DB queries, #{(Thread.current[:db_q][:time]*1000).round(1)} ms"
        end
      end
    end
  end
end
