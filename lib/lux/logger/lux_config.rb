# Output log format
Lux.config.logger_formater do |severity, datetime, progname, msg|
  date = Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L')
  msg  = '%s: %s' % [severity, msg] if severity != 'INFO'
  "[%s] %s\n" % [date, msg]
end

# Logger output
Lux.config.logger_output_location do |name|
  Lux.env.prod? || Lux.env.cli? ? './log/%s.log' % name : STDOUT
end

# Log to scren in development, ignore in production
Lux.config.logger_stdout do |what|
  if Lux.config.log_to_stdout
    out = what.is_a?(Proc) ? what.call : what
    puts out
  end
end