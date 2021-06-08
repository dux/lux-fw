class Object
  def cp data
    data = JSON.pretty_generate(data.to_hash) if data.respond_to?(:to_hash)
    Clipboard.copy data
    'copied'
  end

  # reload code changes
  def reload!
    Lux.config.on_code_reload.call :cli
  end

  # prettify last sql command
  def sql! sql=nil
    require 'niceql'
    puts Niceql::Prettifier.prettify_sql sql || $last_sql_command
  end

  # show method info
  # show User, :secure_hash
  # show User
  # def show klass, m=nil
  #   unless m
  #     klass = klass.class unless klass.respond_to?(:new)
  #     return klass.instance_methods false
  #   end

  #   info = klass.method(m)
  #   puts info.source_location.or([]).join(':').yellow
  #   puts '-'
  #   puts info.source
  #   nil
  # end
end

ARGV[0] = 'console' if ARGV[0] == 'c'

LuxCli.class_eval do
  desc :console, 'Start console'
  def console *args
    require 'amazing_print'
    require './config/app'

    Lux.config.dump_errors   = true
    Lux.config.log_to_stdout = true

    # boot
    Lux()

    # create mock session
    Lux::Current.new '/'

    if File.exist?('./config/console.rb')
      puts '* loading ./config/console.rb'
      require './config/console'
    else
      puts '* ./config/console.rb not found'
    end

    Pry.config.print = proc do |output, value|
      if value.is_a?(Method)
        output.puts value.inspect
      elsif value.is_a?(String)
        output.puts value
      else
        ap value
      end
    end

    if args.first
      command = args.join(' ')

      if command.ends_with?('.rb')
        puts 'Load : %s' % command.light_blue
        load command
      else
        puts 'Command : %s' % command.light_blue
        data = eval command
        puts '-'
        Pry.config.print.call $stdout, data
      end
    else
      Pry.start
    end
  end
end