LuxCli.class_eval do
  desc :evaluate, 'Eval ruby string in context of Lux::Application'
  def evaluate *args
    require './config/application'

    Lux.start

    if File.exist?('./config/console.rb')
      puts '* loading ./config/console.rb'
      load './config/console.rb'
    end

    command = ARGV.drop(1).join('; ')

    puts 'Command : %s' % command.light_blue

    data = eval command

    puts '-'
    puts 'Class   : %s' % data.class
    puts '-'

    if data.class == String && data.include?('</body>')
      require 'nokogiri'
      puts Nokogiri::XML(data, &:noblanks)
    else
      ap data
    end

    exit
  end
end
