module Lux
  CONFIG ||= {}.to_ch

  # get config hash pointer or die if key provided and not found
  def config key=nil
    if key
      value = CONFIG[key]
      die 'Lux.config.%s not found' % key if value.nil?
      value.kind_of?(Proc) ? value.call() : value
    else
      CONFIG
    end
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
