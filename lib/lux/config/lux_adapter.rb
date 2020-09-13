module Lux
  CONFIG ||= {}.to_hwia

  # get config hash pointer or die if key provided and not found
  def config
    CONFIG
  end

  # load rake tasks + including ones in plugins
  def load_tasks
    if ARGV.first.to_s.end_with?(':')
      run 'rake -T | grep %s' % ARGV.first
      exit
    end

    require_relative '../../../tasks/loader'
  end
end
