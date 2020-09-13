# Logs DB queries in console
# to active just load the file
if Lux.config.log_to_stdout
  logger = Logger.new(STDOUT)

  logger.formatter = proc { |severity, datetime, progname, msg|
    elms = msg.split(/\(|s\)\s/, 3)
    time = (elms[1].to_f * 1000).round(1)

    if c = Thread.current[:db_q]
      if c && c[:last] != msg
        c[:last] = msg
        c[:time] += elms[1].to_f
        c[:cnt]  += 1

        if Lux.current.request.params[:sql] == 'true'
          require 'niceql'
          from = caller.find { |el| el.start_with?(Lux.root.to_s) }.split(':in ').first.sub(Lux.root.to_s, '.')
          puts '- %sms - %s' % [(elms[1].to_f * 1000).round(1), from]
          puts Niceql::Prettifier.prettify_sql elms[2]
          puts
        else
          Lux.log " #{c[:cnt].to_s.rjust(2)}. #{time} : #{elms[2].to_s.cyan}\n"
        end
      end
    else
      if ENV['DB_LOG'] || (!Lux.env.rake? && !msg.include?('SELECT "pg_attribute"."attname"') && !msg.end_with?('SELECT NULL'))
        $last_sql_command = msg
        Lux.log ('DB: %s' % msg).cyan
      end
    end
  }

  DB.loggers << logger
end
