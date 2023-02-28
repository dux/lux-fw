LuxCli.class_eval do
  desc :secrets, 'Edit, show and compile secrets'
  def secrets
    require 'lux-fw'

    # show secret for easier debuging and dump secrets
    Cli.info 'dump for ENV %s' % Lux.env

    Cli.info 'dump for secrets'
    puts Lux.secrets.to_h.to_jsonp(true)
  end
end
