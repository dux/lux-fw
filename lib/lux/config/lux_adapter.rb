module Lux
  CONFIG ||= {}.to_hwia

  # get config hash pointer or die if key provided and not found
  def config
    CONFIG
  end

  # load rake tasks + including ones in plugins
  def load_tasks
    name = ARGV.first.to_s

    if name.end_with?(':')
        data = `rake #{name}info 2>&1`

        unless data.include?('rake aborted!')
          puts "rake #{name}".gray
          puts data
          puts '---'
        end

        run 'rake -T | grep --color=never %s' % ARGV.first
      exit
    end

    require_relative '../../../tasks/loader'
  end
end
