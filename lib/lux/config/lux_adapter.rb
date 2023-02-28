module Lux
  # get config hash pointer or die if key provided and not found
  def config
    @lux_config ||= Lux::Config.load.to_hwia
  end
  alias :secrets :config

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
