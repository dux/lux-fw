# require_relative 'simple_exception'

eval File.read Lux.fw_root.join('plugins/log_exceptions/lib/simple_exception.rb')

desc 'Show exceptions'
task :exceptions do
  case ARGV[1]
    when 'help'
      puts ' lux exceptions        - show all exceptions'
      puts ' lux exceptions clear  - to clear error folder'
      puts ' lux exceptions NUMBER - to show error on specific number'
      exit
  end

  show = ARGV[1] ? ARGV[1].to_i : nil
  puts 'Add error number as last argument to show full erros, "clear" to clear all'.light_blue unless show

  cnt = 0

  list = SimpleException.list

  die('No exceptions found') unless list[0]

  list.each do |ex|
    cnt += 1
    next if show && show != cnt

    puts '%s. %s, %s (%s)' % [cnt.to_s.rjust(2), ex[:age].yellow, ex[:desc], ex[:code]]

    if show
      puts "\n" + File.read(ex[:file])
      exit
    end
  end
end

namespace :exceptions do
  desc 'Clear all excpetions'
  task :clear do
    SimpleException.clear
    puts 'Cleared from %s' % SimpleException::ERROR_FOLDER.yellow
  end
end