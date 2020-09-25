# Logs DB queries in console
# to active just load the file
if Lux.config.log_to_stdout
  logger = Logger.new(STDOUT)

  logger.formatter = proc do |severity, datetime, progname, msg|
    elms = msg.split(/\(|s\)\s/, 3)
    time = (elms[1].to_f * 1000).round(1)

    if c = Thread.current[:db_q]
      if c && c[:last] != msg
        c[:last] = msg
        c[:time] += elms[1].to_f
        c[:cnt]  += 1

        if Lux.current.request.params[:sql] == 'true'
          require 'niceql'
          puts '- %sms - %s' % [(elms[1].to_f * 1000).round(1), Lux.app_caller]
          puts Niceql::Prettifier.prettify_sql elms[2]
          puts
        else
          Lux.log do
            line  = " #{c[:cnt].to_s.rjust(2)}. #{time} : #{elms[2].to_s.cyan}"
            line += "-- #{Lux.app_caller}" if Lux.current.no_cache?
            line
          end
        end
      end
    else
      if ENV['DB_LOG'] || (!Lux.env.rake? && !msg.include?('SELECT "pg_attribute"."attname"') && !msg.end_with?('SELECT NULL'))
        $last_sql_command = msg
        Lux.log ('DB: (%s ms) %s' % [time, msg.split('s) ', 2)[1]]).cyan
      end
    end
  end

  DB.loggers << logger

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
