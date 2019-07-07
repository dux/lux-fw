LuxCli.class_eval do
  desc :evaluate, 'Eval ruby string in context of Lux::Application'
  def evaluate *args
    require './config/application'

    # Lux.start

    if File.exist?('./config/console.rb')
      puts '* loading ./config/console.rb'
      load './config/console.rb'
    end

    command = ARGV.drop(1).join(' ')

    if command.ends_with?('.rb')
      puts 'Load : %s' % command.light_blue
      load command
    else
      puts 'Command : %s' % command.light_blue
      data = eval command
      puts '-'
      Pry.config.print.call $stdout, data
    end

    exit
  end
end
