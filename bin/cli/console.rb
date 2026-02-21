class Object
  def cp data
    data = JSON.pretty_generate(data.to_hash) if data.respond_to?(:to_hash)
    Clipboard.copy data
    'copied'
  end

  # reload code changes
  def reload!
    Lux.config.on_reload_code.call :cli
  end

  # prettify last sql command
  def sql! sql=nil
    require 'niceql'
    puts Niceql::Prettifier.prettify_sql sql || $last_sql_command
  end

  def c
    system('clear')
  end

  # show method info
  # m User, :secure_hash
  def m object, mtd = nil
    if mtd
      info = object.method(mtd)
      puts info.source_location.or([]).join(':').colorize(:yellow)
      puts '-'
      puts info.source
      nil
    else
      if object.respond_to?(:superclass)
        object.methods - object.superclass.methods
      else
        object.methods - object.class.superclass.methods
      end
    end
  end
end

ARGV[0] = 'console' if ARGV[0] == 'c'

LuxCli.class_eval do
  desc :console, 'Start console'
  def console *args
    ENV['LUX_ENV'] = 'clre'

    require 'amazing_print'
    require './config/app'

    # create mock session
    Lux::Current.new '/'

    if File.exist?('./config/console.rb')
      puts '* loading ./config/console.rb'
      require './config/console'
    else
      puts '* ./config/console.rb not found'
    end

    Pry.pager = false

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

      if command.end_with?('.rb')
        puts 'Load : %s' % command.colorize(:light_blue)
        load command
      else
        puts 'Command : %s' % command.colorize(:light_blue)
        data = eval command
        puts '-'
        Pry.config.print.call $stdout, data
      end
    else
      # custom history loader
      history = Pathname.new Lux.root.join('./.pry_history')

      Thread.new do
        # load in started pry session
        sleep 0.5
        if history.exist?
          lines = history.read.split($/).uniq - ['exit']
          lines.each {|l| Pry.history.push(l) }
        end
      end
      Pry.start

      history.write Pry.history.to_a.uniq.last(100).join($/)
    end
  end
end
