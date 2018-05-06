LuxCli.class_eval do
  desc :eval, 'Eval ruby string in context of Lux::Application'
  def eval
    require './config/application'

    if File.exist?('./config/console.rb')
      puts '* loading ./config/console.rb'
      load './config/console.rb'
    end

    command = ARGV.join('; ')

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
  end
end
