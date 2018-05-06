LuxCli.class_eval do
  desc :routes, 'Print routes'
  def routes path
    ENV['LUX_PRINT_ROUTES'] = 'true'

    require 'awesome_print'
    require './config/application'

    Lux.config.log_to_stdout = false

    path = ARGV[0] || '/print-routes'

    puts 'Routes for test route %s' % path.green

    Lux.app.render path
  end
end