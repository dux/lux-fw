namespace :exceptions do
  task :list do
    desc 'Show exceptions (pass a number to show a specific one)'
    needs :env

    proc do |opts|
      show = opts[:args].first&.to_i

      unless show
        say.blue 'Add error number as last argument to show full errors, or run exceptions:clear'
      end

      list = Lux::Error::Logger.list
      error 'No exceptions found' unless list[0]

      cnt = 0
      list.each do |ex|
        cnt += 1
        next if show && show != cnt

        puts '%s. %s, %s (%s)' % [cnt.to_s.rjust(2), ex[:age].colorize(:yellow), ex[:desc], ex[:code]]

        if show
          puts "\n" + File.read(ex[:file])
          exit
        end
      end
    end
  end

  task :clear do
    desc 'Clear all exceptions'
    needs :env
    proc do |_opts|
      Lux::Error::Logger.clear
      puts 'Cleared from %s' % Lux::Error::Logger::ERROR_FOLDER.colorize(:yellow)
    end
  end
end
